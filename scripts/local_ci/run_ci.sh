#!/usr/bin/env bash
# =============================================================================
# run_ci.sh — Run OCK external CI pipelines locally on Linux ARM (aarch64)
# =============================================================================
# Replicates the following GitHub Actions jobs from run_ock_external_tests.yml:
#
#   a) SYCL-CTS               (build_sycl_cts_aarch64 + run_sycl_cts_aarch64)
#   b) SYCL on Native CPU     (e2e with DPC++ native_cpu backend, no OCK)
#   c) DPC++ e2e via OpenCL   (run_sycl_e2e_aarch64 with OCK as OpenCL ICD)
#
# Dependencies (installed by step_setup_deps if missing):
#   cmake ninja-build python3 python3-pip git wget gpg ccache
#   spirv-tools libhwloc-dev zstd
#   pip: colorama lit psutil
#
# Usage:
#   ./scripts/local_ci/run_ci.sh [OPTIONS]
#   ./scripts/local_ci/run_ci.sh --help
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration — override via environment or CLI flags
# =============================================================================
: "${WORKSPACE:=$HOME/ock_ci_workspace}"   # All artifacts go here
: "${LLVM_VERSION:=20}"                    # LLVM major version (20, 21)
: "${ARCH:=aarch64}"                       # aarch64 or x86_64
: "${JOBS:=$(nproc)}"                      # Parallel build jobs
: "${DPCPP_SOURCE:=download_release}"      # 'download_release' or 'build'

# Step toggles: set 1=enabled, 0=skip
: "${STEP_SETUP_DEPS:=1}"       # Install system packages if missing
: "${STEP_SETUP_LLVM:=1}"       # Install LLVM via apt from apt.llvm.org
: "${STEP_BUILD_OCK:=1}"        # Build OCK (libCL.so, clc)
: "${STEP_BUILD_ICD:=1}"        # Build OpenCL Headers + ICD Loader
: "${STEP_BUILD_DPCPP:=1}"      # Get DPC++ (download or build from source)
: "${STEP_BUILD_SYCL_CTS:=1}"   # Build SYCL-CTS binaries
: "${STEP_RUN_SYCL_CTS:=1}"     # a) Run SYCL-CTS
: "${STEP_RUN_E2E_OPENCL:=1}"   # c) Run DPC++ e2e via OpenCL (OCK)
: "${STEP_RUN_E2E_NATIVE_CPU:=0}" # b) Run DPC++ e2e via native_cpu (opt-in)

# Force rebuild even if artifact directories already exist
: "${FORCE_REBUILD:=0}"

# =============================================================================
# Internal derived paths (do not edit)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCK_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET="host_${ARCH}_linux"
LLVM_INSTALL="$WORKSPACE/llvm_install"
OCK_INSTALL="$WORKSPACE/install"
ICD_INSTALL="$WORKSPACE/install_icd"
OCL_HEADERS_INSTALL="$WORKSPACE/install_opencl_headers"
DPCPP_INSTALL="$WORKSPACE/dpcpp/${ARCH}-linux/install"
BUILD_E2E_OPENCL="$WORKSPACE/build_e2e_opencl"
BUILD_E2E_NATIVE="$WORKSPACE/build_e2e_native_cpu"

# =============================================================================
# Helpers
# =============================================================================
log()  { echo -e "\n\033[1;34m[$(date '+%H:%M:%S')] >>> $*\033[0m"; }
ok()   { echo -e "  \033[1;32m✓ $*\033[0m"; }
warn() { echo -e "  \033[1;33m⚠ $*\033[0m"; }
die()  { echo -e "\033[1;31m✗ ERROR: $*\033[0m" >&2; exit 1; }

should_skip() {
    # Returns 0 (skip) when artifact dir exists and FORCE_REBUILD=0
    local dir="$1"
    [[ "$FORCE_REBUILD" -eq 0 && -e "$dir" ]]
}

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Replicates OCK GitHub Actions CI pipelines locally on Linux ARM.

BUILD OPTIONS:
  --workspace DIR       Working dir for all artifacts  [default: ~/ock_ci_workspace]
  --llvm-version VER    LLVM major version: 20, 21     [default: 20]
  --arch ARCH           Target arch: aarch64, x86_64   [default: aarch64]
  --jobs N              Parallel build jobs            [default: nproc = $(nproc)]
  --dpcpp-source SRC    DPC++ source: 'download_release' or 'build'
                                                       [default: download_release]
  --force-rebuild       Rebuild artifacts even if they already exist

STEP SELECTION:
  --only-sycl-cts       Build everything + run only SYCL-CTS (a)
  --only-e2e-opencl     Build everything + run only DPC++ e2e via OpenCL (c)
  --only-e2e-native     Build everything + run only DPC++ e2e via Native CPU (b)
  --all-tests           Run all three test suites (enables native CPU)
  --tests-only          Skip all build steps, only run tests (artifacts must exist)
  --skip-llvm           Skip LLVM installation step
  --skip-ock-build      Skip OCK build step
  --skip-dpcpp          Skip DPC++ build step
  --with-native-cpu     Also run DPC++ e2e via native_cpu backend (b)
  --no-sycl-cts         Disable SYCL-CTS run
  --no-e2e-opencl       Disable DPC++ e2e via OpenCL run

ENVIRONMENT OVERRIDES:
  WORKSPACE, LLVM_VERSION, ARCH, JOBS, DPCPP_SOURCE, FORCE_REBUILD
  STEP_SETUP_DEPS, STEP_SETUP_LLVM, STEP_BUILD_OCK, STEP_BUILD_ICD,
  STEP_BUILD_DPCPP, STEP_BUILD_SYCL_CTS, STEP_RUN_SYCL_CTS,
  STEP_RUN_E2E_OPENCL, STEP_RUN_E2E_NATIVE_CPU

EXAMPLES:
  # Full run (builds everything, runs SYCL-CTS + e2e via OpenCL):
  $0

  # Only SYCL-CTS (still builds all required artifacts):
  $0 --only-sycl-cts

  # Re-run tests without rebuilding (artifacts from previous run):
  $0 --tests-only

  # Run all tests including Native CPU:
  $0 --all-tests

  # Build DPC++ from source instead of downloading:
  $0 --dpcpp-source build

  # Rebuild OCK only:
  STEP_SETUP_LLVM=0 STEP_BUILD_ICD=0 STEP_BUILD_DPCPP=0 \\
  STEP_BUILD_SYCL_CTS=0 STEP_RUN_SYCL_CTS=0 STEP_RUN_E2E_OPENCL=0 \\
  FORCE_REBUILD=1 $0

EOF
    exit 0
}

# =============================================================================
# Argument parsing
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)        WORKSPACE="$2";       shift 2 ;;
        --llvm-version)     LLVM_VERSION="$2";    shift 2 ;;
        --arch)             ARCH="$2"; TARGET="host_${ARCH}_linux"; shift 2 ;;
        --jobs)             JOBS="$2";             shift 2 ;;
        --dpcpp-source)     DPCPP_SOURCE="$2";    shift 2 ;;
        --force-rebuild)    FORCE_REBUILD=1;       shift ;;
        --only-sycl-cts)
            STEP_RUN_SYCL_CTS=1; STEP_RUN_E2E_OPENCL=0; STEP_RUN_E2E_NATIVE_CPU=0
            shift ;;
        --only-e2e-opencl)
            STEP_RUN_SYCL_CTS=0; STEP_RUN_E2E_OPENCL=1; STEP_RUN_E2E_NATIVE_CPU=0
            STEP_BUILD_SYCL_CTS=0
            shift ;;
        --only-e2e-native)
            STEP_RUN_SYCL_CTS=0; STEP_RUN_E2E_OPENCL=0; STEP_RUN_E2E_NATIVE_CPU=1
            STEP_BUILD_SYCL_CTS=0
            shift ;;
        --all-tests)
            STEP_RUN_SYCL_CTS=1; STEP_RUN_E2E_OPENCL=1; STEP_RUN_E2E_NATIVE_CPU=1
            shift ;;
        --tests-only)
            STEP_SETUP_DEPS=0; STEP_SETUP_LLVM=0; STEP_BUILD_OCK=0
            STEP_BUILD_ICD=0; STEP_BUILD_DPCPP=0; STEP_BUILD_SYCL_CTS=0
            shift ;;
        --skip-llvm)        STEP_SETUP_LLVM=0;    shift ;;
        --skip-ock-build)   STEP_BUILD_OCK=0;     shift ;;
        --skip-dpcpp)       STEP_BUILD_DPCPP=0;   shift ;;
        --with-native-cpu)  STEP_RUN_E2E_NATIVE_CPU=1; shift ;;
        --no-sycl-cts)      STEP_RUN_SYCL_CTS=0; STEP_BUILD_SYCL_CTS=0; shift ;;
        --no-e2e-opencl)    STEP_RUN_E2E_OPENCL=0; shift ;;
        -h|--help)          usage ;;
        *) die "Unknown option: '$1' — run with --help for usage" ;;
    esac
done

# Recompute derived paths after arg parsing
TARGET="host_${ARCH}_linux"
LLVM_INSTALL="$WORKSPACE/llvm_install"
OCK_INSTALL="$WORKSPACE/install"
ICD_INSTALL="$WORKSPACE/install_icd"
OCL_HEADERS_INSTALL="$WORKSPACE/install_opencl_headers"
DPCPP_INSTALL="$WORKSPACE/dpcpp/${ARCH}-linux/install"

# =============================================================================
# Preflight checks
# =============================================================================
[[ -f "$OCK_SRC/CMakeLists.txt" ]] \
    || die "OCK source not found at $OCK_SRC (script must live inside the repo)"

mkdir -p "$WORKSPACE"

log "OCK Local CI — Configuration"
cat <<EOF
  OCK source  : $OCK_SRC
  Workspace   : $WORKSPACE
  Target      : $TARGET (arch=$ARCH)
  LLVM        : $LLVM_VERSION
  DPC++       : $DPCPP_SOURCE
  Jobs        : $JOBS
  Force build : $FORCE_REBUILD

  Steps enabled:
    setup_deps=$STEP_SETUP_DEPS  setup_llvm=$STEP_SETUP_LLVM
    build_ock=$STEP_BUILD_OCK    build_icd=$STEP_BUILD_ICD
    build_dpcpp=$STEP_BUILD_DPCPP  build_sycl_cts=$STEP_BUILD_SYCL_CTS
    run_sycl_cts=$STEP_RUN_SYCL_CTS
    run_e2e_opencl=$STEP_RUN_E2E_OPENCL
    run_e2e_native_cpu=$STEP_RUN_E2E_NATIVE_CPU
EOF

# =============================================================================
# Step: Install system dependencies
# =============================================================================
step_setup_deps() {
    log "STEP 0: Install system dependencies"

    local pkgs_needed=()
    for pkg in cmake ninja-build python3 python3-pip git wget gpg ccache \
                spirv-tools libhwloc-dev zstd; do
        dpkg -s "$pkg" &>/dev/null || pkgs_needed+=("$pkg")
    done

    if [[ ${#pkgs_needed[@]} -gt 0 ]]; then
        log "  Installing: ${pkgs_needed[*]}"
        sudo apt-get update -q
        sudo apt-get install -y "${pkgs_needed[@]}"
    else
        ok "All system packages already installed"
    fi

    pip install colorama lit psutil -q
    ok "Python packages ready"
}

# =============================================================================
# Step: Install LLVM via apt
# =============================================================================
step_setup_llvm() {
    log "STEP 1: Install LLVM ${LLVM_VERSION}"

    if should_skip "$LLVM_INSTALL"; then
        ok "LLVM already at $LLVM_INSTALL — skipping (use --force-rebuild to redo)"
        return
    fi

    local codename
    codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")

    wget -qO - https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor \
        | sudo tee /usr/share/keyrings/llvm-archive-keyring.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] \
http://apt.llvm.org/${codename}/ llvm-toolchain-${codename}-${LLVM_VERSION} main" \
        | sudo tee /etc/apt/sources.list.d/llvm.list

    sudo apt-get update -q
    sudo apt-get install -y \
        "llvm-${LLVM_VERSION}-dev" \
        "liblld-${LLVM_VERSION}-dev" \
        "libclang-${LLVM_VERSION}-dev" \
        "libpolly-${LLVM_VERSION}-dev" \
        "clang-${LLVM_VERSION}"

    ln -sfn "/usr/lib/llvm-${LLVM_VERSION}" "$LLVM_INSTALL"
    ok "LLVM ${LLVM_VERSION} → $LLVM_INSTALL"
}

# =============================================================================
# Step: Build OCK (libCL.so + clc)
# =============================================================================
step_build_ock() {
    log "STEP 2: Build OCK artifact"

    if should_skip "$OCK_INSTALL/lib/libCL.so"; then
        ok "OCK already at $OCK_INSTALL — skipping"
        return
    fi

    cmake -GNinja \
        -B"$WORKSPACE/build_ock" \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCA_MUX_TARGETS_TO_ENABLE=host \
        -DCA_MUX_COMPILERS_TO_ENABLE=host \
        -DCA_LLVM_INSTALL_DIR="$LLVM_INSTALL" \
        -DCMAKE_BUILD_TYPE=ReleaseAssert \
        -DCA_ENABLE_DEBUG_SUPPORT=OFF \
        -DCA_ENABLE_HOST_IMAGE_SUPPORT=OFF \
        -DCA_HOST_ENABLE_BUILTIN_KERNEL=OFF \
        -DCA_HOST_ENABLE_BUILTINS_EXTENSION=ON \
        -DCA_HOST_ENABLE_FP16=OFF \
        -DCA_CL_ENABLE_OFFLINE_KERNEL_TESTS=OFF \
        -DOCL_EXTENSION_cl_intel_unified_shared_memory=ON \
        -DOCL_EXTENSION_cl_khr_command_buffer=ON \
        -DOCL_EXTENSION_cl_khr_command_buffer_mutable_dispatch=ON \
        -DCA_CL_ENABLE_ICD_LOADER=ON \
        -DCA_ENABLE_TESTS=OFF \
        -DCA_ENABLE_EXAMPLES=OFF \
        -DCA_ENABLE_DOCUMENTATION=OFF \
        -DCMAKE_INSTALL_PREFIX="$OCK_INSTALL" \
        "$OCK_SRC"

    ninja -C "$WORKSPACE/build_ock" install

    # Prune to match the CI artifact (only clc, *.py, and libs are kept)
    find "$OCK_INSTALL/bin" -maxdepth 1 -type f \
        ! \( -name "*.py" -o -name "*clc" \) -delete
    rm -rf "$OCK_INSTALL/share"
    ok "OCK → $OCK_INSTALL"
}

# =============================================================================
# Step: Build OpenCL Headers + ICD Loader
# =============================================================================
step_build_icd() {
    log "STEP 3: Build OpenCL Headers + ICD Loader"

    if should_skip "$ICD_INSTALL/lib/libOpenCL.so"; then
        ok "ICD already at $ICD_INSTALL — skipping"
        return
    fi

    # OpenCL Headers
    if [[ ! -d "$WORKSPACE/opencl_headers" ]]; then
        git clone --depth 1 \
            https://github.com/KhronosGroup/OpenCL-Headers \
            "$WORKSPACE/opencl_headers"
    fi
    cmake "$WORKSPACE/opencl_headers" \
        -B"$WORKSPACE/build_opencl_headers" \
        -DCMAKE_INSTALL_PREFIX="$OCL_HEADERS_INSTALL" \
        -GNinja
    ninja -C "$WORKSPACE/build_opencl_headers" install

    # ICD Loader
    if [[ ! -d "$WORKSPACE/opencl_icd" ]]; then
        git clone --depth 1 \
            https://github.com/KhronosGroup/OpenCL-ICD-Loader \
            "$WORKSPACE/opencl_icd"
    fi
    cmake "$WORKSPACE/opencl_icd" \
        -B"$WORKSPACE/build_icd" \
        -DCMAKE_INSTALL_PREFIX="$ICD_INSTALL" \
        -DOpenCLHeaders_DIR="$OCL_HEADERS_INSTALL/share/cmake/OpenCLHeaders" \
        -GNinja
    ninja -C "$WORKSPACE/build_icd" install
    ok "ICD → $ICD_INSTALL"
}

# =============================================================================
# Step: Get DPC++ (download nightly or build from source)
# =============================================================================
step_build_dpcpp() {
    log "STEP 4: Get DPC++ (${DPCPP_SOURCE})"

    if should_skip "$DPCPP_INSTALL/bin/clang++"; then
        ok "DPC++ already at $DPCPP_INSTALL — skipping"
        return
    fi

    mkdir -p "$DPCPP_INSTALL"

    if [[ "$DPCPP_SOURCE" == "download_release" ]]; then
        log "  Downloading latest nightly DPC++ release from intel/llvm..."
        local downloaded=0
        for counter in {0..13}; do
            local datestamp
            datestamp=$(date -d "-${counter} day" '+%Y-%m-%d')
            local url="https://github.com/intel/llvm/releases/download/nightly-${datestamp}/sycl_linux.tar.gz"
            if wget -q --show-progress "$url" -O "$WORKSPACE/sycl_linux.tar.gz"; then
                log "  Using DPC++ nightly: ${datestamp}"
                tar xf "$WORKSPACE/sycl_linux.tar.gz" -C "$DPCPP_INSTALL"
                rm "$WORKSPACE/sycl_linux.tar.gz"
                downloaded=1
                break
            fi
        done
        [[ $downloaded -eq 1 ]] || die "Failed to download DPC++ nightly (tried 14 days)"

    else
        # Build from source (matches build_dpcpp_native_aarch64 job exactly)
        log "  Building DPC++ from source (intel/llvm)..."

        local dpcpp_src="$WORKSPACE/llvm_dpcpp"
        if [[ ! -d "$dpcpp_src" ]]; then
            git clone https://github.com/intel/llvm "$dpcpp_src"
        fi

        # Apply OCK-specific DPC++ patches
        for patch in "$OCK_SRC"/scripts/testing/patches/DPCPP-*.patch; do
            [[ -f "$patch" ]] && { log "  Applying ${patch##*/}"; git -C "$dpcpp_src" apply "$patch"; }
        done

        cd "$dpcpp_src"
        python3 buildbot/configure.py -o "build/${ARCH}-linux" \
            --host-target="X86;AArch64;RISCV" \
            --llvm-external-projects=lld \
            --cmake-opt=-DLLVM_ENABLE_ZLIB=OFF \
            --cmake-opt=-DLLVM_ENABLE_ZSTD=OFF \
            --cmake-opt=-DLLVM_CCACHE_BUILD=ON

        cmake --build "build/${ARCH}-linux" -- sycl-headers
        python3 buildbot/compile.py -o "build/${ARCH}-linux" -v -j "${JOBS}"
        cmake --build "build/${ARCH}-linux" -- \
            FileCheck clang-tblgen llvm-as llvm-min-tblgen llvm-tblgen not opt -j "${JOBS}"

        # Copy extra utilities to install/bin (needed for cross-compilation)
        pushd "build/${ARCH}-linux/bin" >/dev/null
        cp FileCheck clang-tblgen llvm-as llvm-min-tblgen llvm-tblgen not opt ../install/bin
        popd >/dev/null

        # Config files to pick up cross-arch libraries
        for arch_cfg in x86_64 aarch64; do
            printf -- '-L<CFGDIR>/../../../%s-linux/install/lib\n' "$arch_cfg" \
                > "build/${ARCH}-linux/install/bin/${arch_cfg}-unknown-linux-gnu.cfg"
        done

        cd "$WORKSPACE"
    fi

    ok "DPC++ → $DPCPP_INSTALL"
}

# =============================================================================
# Step: Build SYCL-CTS
# =============================================================================
step_build_sycl_cts() {
    log "STEP 5: Build SYCL-CTS"

    if should_skip "$WORKSPACE/SYCL-CTS/bin"; then
        ok "SYCL-CTS already at $WORKSPACE/SYCL-CTS/bin — skipping"
        return
    fi

    if [[ ! -d "$WORKSPACE/SYCL-CTS.src" ]]; then
        git clone --recurse-submodules \
            https://github.com/KhronosGroup/SYCL-CTS \
            "$WORKSPACE/SYCL-CTS.src"
    fi

    # Apply OCK-specific SYCL-CTS patches
    for patch in "$OCK_SRC"/scripts/testing/patches/SYCL-CTS-*.patch; do
        [[ -f "$patch" ]] && { log "  Applying ${patch##*/}"; git -C "$WORKSPACE/SYCL-CTS.src" apply "$patch"; }
    done

    # Build all test categories (CI splits A/B/C in parallel; we build sequentially)
    cmake -S "$WORKSPACE/SYCL-CTS.src" -GNinja -B "$WORKSPACE/SYCL-CTS" \
        -DSYCL_IMPLEMENTATION=DPCPP \
        -DDPCPP_INSTALL_DIR="$DPCPP_INSTALL" \
        -DCMAKE_CXX_COMPILER="$DPCPP_INSTALL/bin/clang++" \
        -DCMAKE_CXX_FLAGS="--target=${ARCH}-linux-gnu" \
        -DCMAKE_CXX_LINK_FLAGS="-fuse-ld=lld" \
        -DOpenCL_LIBRARY="$ICD_INSTALL/lib/libOpenCL.so" \
        -DOpenCL_INCLUDE_DIR="$OCL_HEADERS_INSTALL/include" \
        -DDPCPP_FLAGS=--offload-new-driver

    # -k 0: keep going even if individual test targets fail to build
    ninja -C "$WORKSPACE/SYCL-CTS" -v -j4 -k 0 || \
        warn "Some SYCL-CTS targets failed to build (continuing)"

    ok "SYCL-CTS → $WORKSPACE/SYCL-CTS/bin"
}

# =============================================================================
# Helper: Clone/update intel/llvm for e2e tests (sparse: sycl/test-e2e only)
# =============================================================================
_ensure_sycl_e2e_src() {
    if [[ ! -d "$WORKSPACE/llvm_e2e/sycl/test-e2e" ]]; then
        log "  Cloning intel/llvm (sparse checkout: sycl/test-e2e)..."
        git clone --filter=blob:none --no-checkout \
            https://github.com/intel/llvm "$WORKSPACE/llvm_e2e"
        git -C "$WORKSPACE/llvm_e2e" sparse-checkout set sycl/test-e2e
        git -C "$WORKSPACE/llvm_e2e" checkout
    fi
}

# =============================================================================
# Test a) SYCL-CTS
# =============================================================================
run_sycl_cts() {
    log "TEST a) SYCL-CTS  (target=${TARGET}, llvm=${LLVM_VERSION})"

    [[ -d "$WORKSPACE/SYCL-CTS/bin" ]] \
        || die "SYCL-CTS binaries not found. Run with STEP_BUILD_SYCL_CTS=1 first."
    [[ -f "$OCK_INSTALL/lib/libCL.so" ]] \
        || die "OCK libCL.so not found at $OCK_INSTALL/lib/. Run with STEP_BUILD_OCK=1 first."

    export LD_LIBRARY_PATH="${DPCPP_INSTALL}/lib:${OCK_INSTALL}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export ONEAPI_DEVICE_SELECTOR=opencl:0
    export OCL_ICD_FILENAMES="${OCK_INSTALL}/lib/libCL.so"

    # Build combined override file (all.csv + target-specific overrides)
    python3 "$OCK_SRC/scripts/testing/create_override_csv.py" \
        -d "$OCK_SRC/scripts/testing/sycl_cts" \
        -k "${TARGET}" "llvm_${LLVM_VERSION}" \
        -o "$WORKSPACE/sycl_cts_override.csv" -vv

    python3 "$OCK_SRC/scripts/testing/run_cities.py" \
        --color=always \
        --timeout 03:30:00 \
        -p sycl_cts \
        -b "$WORKSPACE/SYCL-CTS/bin" \
        -L "$WORKSPACE/SYCL-CTS/lib" \
        -s "$OCK_SRC/scripts/testing/sycl_cts/tests.csv" \
        -l "$WORKSPACE/sycl_cts.log" \
        -f "$WORKSPACE/sycl_cts.fail" \
        -r "$WORKSPACE/sycl_cts.xml" \
        -v \
        -o "$WORKSPACE/sycl_cts_override.csv"

    ok "SYCL-CTS results: $WORKSPACE/sycl_cts.log"
}

# =============================================================================
# Test c) DPC++ e2e via OpenCL (OCK as ICD)
# =============================================================================
run_sycl_e2e_opencl() {
    log "TEST c) DPC++ e2e via OpenCL  (target=${TARGET})"

    [[ -f "$OCK_INSTALL/lib/libCL.so" ]] \
        || die "OCK libCL.so not found. Run with STEP_BUILD_OCK=1 first."

    _ensure_sycl_e2e_src

    if should_skip "$BUILD_E2E_OPENCL/build.ninja"; then
        ok "e2e (OpenCL) already configured — skipping cmake"
    else
        # Remove opencl-aot binary (required by the e2e cmake configuration)
        rm -f "$DPCPP_INSTALL/bin/opencl-aot"

        CC="$DPCPP_INSTALL/bin/clang" \
        CXX="$DPCPP_INSTALL/bin/clang++" \
        cmake -GNinja -B"$BUILD_E2E_OPENCL" \
            "$WORKSPACE/llvm_e2e/sycl/test-e2e" \
            -DSYCL_TEST_E2E_TARGETS=opencl:cpu
    fi

    # Build override: known.csv + target-specific overrides
    python3 "$OCK_SRC/scripts/testing/create_override_csv.py" \
        -d "$OCK_SRC/scripts/testing/sycl_e2e" \
        -k "${TARGET}" \
        -o "$WORKSPACE/e2e_opencl_override.csv" -vv

    cat "$OCK_SRC/scripts/testing/sycl_e2e/known.csv" \
        "$WORKSPACE/e2e_opencl_override.csv" \
        > "$WORKSPACE/e2e_opencl_known_override.csv"

    export LD_LIBRARY_PATH="${ICD_INSTALL}/lib:${DPCPP_INSTALL}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    python3 -u "$OCK_SRC/scripts/testing/run_cities.py" \
        -e OCL_ICD_FILENAMES="${OCK_INSTALL}/lib/libCL.so" \
        -p lit \
        --lit_dir "$BUILD_E2E_OPENCL" \
        --timeout 1800 \
        -o "$WORKSPACE/e2e_opencl_known_override.csv" \
        --default-unknown

    ok "DPC++ e2e (OpenCL) complete"
}

# =============================================================================
# Test b) DPC++ e2e via Native CPU (DPC++ native_cpu backend, no OCK)
# =============================================================================
run_sycl_e2e_native_cpu() {
    log "TEST b) DPC++ e2e via Native CPU  (target=${TARGET})"

    _ensure_sycl_e2e_src

    if should_skip "$BUILD_E2E_NATIVE/build.ninja"; then
        ok "e2e (native_cpu) already configured — skipping cmake"
    else
        CC="$DPCPP_INSTALL/bin/clang" \
        CXX="$DPCPP_INSTALL/bin/clang++" \
        cmake -GNinja -B"$BUILD_E2E_NATIVE" \
            "$WORKSPACE/llvm_e2e/sycl/test-e2e" \
            -DSYCL_TEST_E2E_TARGETS=native_cpu:cpu
    fi

    python3 "$OCK_SRC/scripts/testing/create_override_csv.py" \
        -d "$OCK_SRC/scripts/testing/sycl_e2e" \
        -k "${TARGET}" \
        -o "$WORKSPACE/e2e_native_override.csv" -vv

    cat "$OCK_SRC/scripts/testing/sycl_e2e/known.csv" \
        "$WORKSPACE/e2e_native_override.csv" \
        > "$WORKSPACE/e2e_native_known_override.csv"

    export ONEAPI_DEVICE_SELECTOR=native_cpu:*
    export LD_LIBRARY_PATH="${DPCPP_INSTALL}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    python3 -u "$OCK_SRC/scripts/testing/run_cities.py" \
        -p lit \
        --lit_dir "$BUILD_E2E_NATIVE" \
        --timeout 1800 \
        -o "$WORKSPACE/e2e_native_known_override.csv" \
        --default-unknown

    ok "DPC++ e2e (Native CPU) complete"
}

# =============================================================================
# Main
# =============================================================================
[[ $STEP_SETUP_DEPS     -eq 1 ]] && step_setup_deps
[[ $STEP_SETUP_LLVM     -eq 1 ]] && step_setup_llvm
[[ $STEP_BUILD_OCK      -eq 1 ]] && step_build_ock
[[ $STEP_BUILD_ICD      -eq 1 ]] && step_build_icd
[[ $STEP_BUILD_DPCPP    -eq 1 ]] && step_build_dpcpp
[[ $STEP_BUILD_SYCL_CTS -eq 1 ]] && step_build_sycl_cts

[[ $STEP_RUN_SYCL_CTS       -eq 1 ]] && run_sycl_cts
[[ $STEP_RUN_E2E_OPENCL     -eq 1 ]] && run_sycl_e2e_opencl
[[ $STEP_RUN_E2E_NATIVE_CPU -eq 1 ]] && run_sycl_e2e_native_cpu

log "All requested steps completed."
