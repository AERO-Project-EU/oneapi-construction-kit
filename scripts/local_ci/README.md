# OCK Local CI — Linux ARM (aarch64)

Replicates the following GitHub Actions jobs from `run_ock_external_tests.yml` locally:

| Label | CI Job | Description |
|-------|--------|-------------|
| a) | `build_sycl_cts_aarch64` + `run_sycl_cts_aarch64` | SYCL-CTS |
| b) | *(opt-in)* | DPC++ e2e via `native_cpu` backend |
| c) | `run_sycl_e2e_aarch64` | DPC++ e2e via OpenCL (OCK as ICD) |

---

## Quick Start

```bash
# Full run — builds everything, then runs SYCL-CTS + DPC++ e2e via OpenCL:
./scripts/local_ci/run_ci.sh

# Only SYCL-CTS (a):
./scripts/local_ci/run_ci.sh --only-sycl-cts

# Only DPC++ e2e via OpenCL (c):
./scripts/local_ci/run_ci.sh --only-e2e-opencl

# All test categories including Native CPU (b):
./scripts/local_ci/run_ci.sh --all-tests

# Re-run tests without rebuilding (artifacts from a previous run):
./scripts/local_ci/run_ci.sh --tests-only
```

---

## Prerequisites

The script installs missing packages automatically (`STEP_SETUP_DEPS=1` by default).
Required system packages:

```
cmake  ninja-build  python3  python3-pip  git  wget  gpg
ccache  spirv-tools  libhwloc-dev  zstd
```

Required pip packages: `colorama lit psutil`

The container image used by CI is `ghcr.io/uxlfoundation/ock_ubuntu_22.04-aarch64:latest`
(built from `.github/dockerfiles/Dockerfile_22.04-aarch64`).

### Running inside Docker (avoids sudo requirements on the host)

The script uses `sudo` only to install system packages and LLVM. If you don't
have sudo on the host, run the script inside the CI container instead — you are
root inside the container so all `sudo` calls succeed without a password.

**Step 1 — Check Docker access:**

```bash
# Does the docker group exist?
getent group docker

# Is your user in it?
groups $USER
```

If you get `permission denied while trying to connect to the Docker socket`, fix it with one of:

```bash
# Add yourself to the docker group (requires sudo once, then no sudo for docker):
sudo usermod -aG docker $USER
newgrp docker          # apply without logging out

# Or use Podman — a rootless drop-in replacement (replace 'docker' with 'podman'):
sudo apt-get install -y podman
```

**Step 2 — Pull and run:**

```bash
docker pull ghcr.io/uxlfoundation/ock_ubuntu_22.04-aarch64:latest

docker run --rm -it \
  -v $PWD:/workspace \
  -v $HOME/ock_ci_workspace:/root/ock_ci_workspace \
  ghcr.io/uxlfoundation/ock_ubuntu_22.04-aarch64:latest bash
```

**Step 3 — Inside the container, run the script normally:**

```bash
cd /workspace
WORKSPACE=/root/ock_ci_workspace ./scripts/local_ci/run_ci.sh
```

---

## Build Pipeline

Each step caches its output directory. If the target already exists, the step is
skipped (override with `--force-rebuild`).

```
Step 0  setup_deps    — apt install + pip install
Step 1  setup_llvm    — install LLVM 20 from apt.llvm.org → llvm_install/
Step 2  build_ock     — build OCK (libCL.so + clc)       → install/
Step 3  build_icd     — OpenCL Headers + ICD Loader       → install_icd/  install_opencl_headers/
Step 4  build_dpcpp   — get DPC++ (download or build)     → dpcpp/aarch64-linux/install/
Step 5  build_sycl_cts— build SYCL-CTS binaries           → SYCL-CTS/bin/
```

All artifacts are written to `WORKSPACE` (default: `~/ock_ci_workspace/`).

### LLVM

Installed via `apt` from `apt.llvm.org`. Default version: **20**.

```bash
# Packages installed:
llvm-20-dev  liblld-20-dev  libclang-20-dev  libpolly-20-dev  clang-20
# Symlinked to:
$WORKSPACE/llvm_install -> /usr/lib/llvm-20
```

### OCK

Built natively on ARM — **no cross-compilation toolchain needed**.
CMake flags used (matching `do_build_ock_artefact` + `do_build_ock` actions):

```cmake
-DCA_MUX_TARGETS_TO_ENABLE=host
-DCA_MUX_COMPILERS_TO_ENABLE=host
-DCA_LLVM_INSTALL_DIR=<llvm_install>
-DCMAKE_BUILD_TYPE=ReleaseAssert
-DCA_CL_ENABLE_ICD_LOADER=ON
-DOCL_EXTENSION_cl_intel_unified_shared_memory=ON
-DOCL_EXTENSION_cl_khr_command_buffer=ON
-DOCL_EXTENSION_cl_khr_command_buffer_mutable_dispatch=ON
-DCA_ENABLE_TESTS=OFF  -DCA_ENABLE_EXAMPLES=OFF  -DCA_ENABLE_DOCUMENTATION=OFF
```

The install directory is pruned to match the CI artifact (only `libCL.so`, `clc`, and `*.py` kept).

### DPC++

Two options controlled by `--dpcpp-source`:

| Option | Description | Time |
|--------|-------------|------|
| `download_release` *(default)* | Downloads latest nightly tarball from `intel/llvm` GitHub releases | ~5 min |
| `build` | Clones `intel/llvm` and builds from source | 2–4 h on ARM |

When downloading, the script tries up to 14 days back to find a published nightly.

OCK-specific patches from `scripts/testing/patches/DPCPP-*.patch` are applied
when building from source.

### SYCL-CTS

Cloned from `KhronosGroup/SYCL-CTS` with submodules.
Patches from `scripts/testing/patches/SYCL-CTS-*.patch` are applied.

CMake flags (matching `do_build_sycl_cts` action):

```cmake
-DSYCL_IMPLEMENTATION=DPCPP
-DDPCPP_INSTALL_DIR=<dpcpp_install>
-DCMAKE_CXX_COMPILER=<dpcpp>/bin/clang++
-DCMAKE_CXX_FLAGS="--target=aarch64-linux-gnu"
-DCMAKE_CXX_LINK_FLAGS="-fuse-ld=lld"
-DOpenCL_LIBRARY=<icd>/lib/libOpenCL.so
-DOpenCL_INCLUDE_DIR=<opencl_headers>/include
-DDPCPP_FLAGS=--offload-new-driver
```

Built with `-j4` (intentional — higher parallelism causes OOM on ARM).
The CI splits this into 3 parallel subset jobs (A/B/C); the script builds all categories
sequentially.

---

## Test Execution

### a) SYCL-CTS

```bash
./scripts/local_ci/run_ci.sh --only-sycl-cts
# or just the run step if artifacts exist:
STEP_BUILD_SYCL_CTS=0 ./scripts/local_ci/run_ci.sh --only-sycl-cts --tests-only
```

Environment set by the script (matching `run_sycl_cts` action):

```bash
ONEAPI_DEVICE_SELECTOR=opencl:0
OCL_ICD_FILENAMES=$WORKSPACE/install/lib/libCL.so
LD_LIBRARY_PATH=<dpcpp>/lib:<ock>/lib
```

Override/known files used:
- `scripts/testing/sycl_cts/tests.csv` — test list
- `scripts/testing/sycl_cts/override_all.csv` — global known failures
- `scripts/testing/sycl_cts/override_host_aarch64_linux.csv` — aarch64-specific
- Per-LLVM-version overrides generated by `create_override_csv.py`

Timeout: **3h 30m** (matches CI).

Results written to:
```
$WORKSPACE/sycl_cts.log
$WORKSPACE/sycl_cts.fail
$WORKSPACE/sycl_cts.xml
```

### c) DPC++ e2e via OpenCL

```bash
./scripts/local_ci/run_ci.sh --only-e2e-opencl
```

Clones `intel/llvm` (sparse: `sycl/test-e2e` only) and configures with:

```cmake
-DSYCL_TEST_E2E_TARGETS=opencl:cpu
```

`OCL_ICD_FILENAMES` is set to OCK's `libCL.so` so that all OpenCL calls go through
OCK's host backend.

Override/known files used:
- `scripts/testing/sycl_e2e/known.csv`
- `scripts/testing/sycl_e2e/override_all.csv`
- `scripts/testing/sycl_e2e/override_host_aarch64_linux.csv`

Timeout: **30 min** (1800 s, matches CI).

### b) DPC++ e2e via Native CPU (opt-in)

```bash
./scripts/local_ci/run_ci.sh --with-native-cpu
# or together with all tests:
./scripts/local_ci/run_ci.sh --all-tests
```

Configures the e2e suite with:

```cmake
-DSYCL_TEST_E2E_TARGETS=native_cpu:cpu
```

Uses `ONEAPI_DEVICE_SELECTOR=native_cpu:*`. Does **not** use OCK — this exercises
DPC++'s own native CPU SYCL backend.

> **Note:** This is disabled by default because the repo's override CSV files are
> tuned for the OpenCL path. Expect a higher unknown/fail count until
> `scripts/testing/sycl_e2e/` is extended with native_cpu-specific overrides.

---

## CLI Reference

```
./scripts/local_ci/run_ci.sh [OPTIONS]

BUILD OPTIONS:
  --workspace DIR       Working dir for all artifacts  [default: ~/ock_ci_workspace]
  --llvm-version VER    LLVM major version: 20, 21     [default: 20]
  --arch ARCH           Target arch: aarch64, x86_64   [default: aarch64]
  --jobs N              Parallel build jobs            [default: nproc]
  --dpcpp-source SRC    'download_release' or 'build'  [default: download_release]
  --force-rebuild       Rebuild artifacts even if they already exist

STEP SELECTION:
  --only-sycl-cts       Build everything + run only SYCL-CTS (a)
  --only-e2e-opencl     Build everything + run only DPC++ e2e via OpenCL (c)
  --only-e2e-native     Build everything + run only DPC++ e2e via Native CPU (b)
  --all-tests           Run all three test suites (enables native CPU)
  --tests-only          Skip all build steps, only run tests
  --skip-llvm           Skip LLVM installation step
  --skip-ock-build      Skip OCK build step
  --skip-dpcpp          Skip DPC++ build step
  --with-native-cpu     Also run DPC++ e2e via native_cpu (b)
  --no-sycl-cts         Disable SYCL-CTS run
  --no-e2e-opencl       Disable DPC++ e2e via OpenCL run
```

All flags can also be set as environment variables:

```bash
WORKSPACE=/fast/ssd/ock_ci \
LLVM_VERSION=21 \
DPCPP_SOURCE=download_release \
STEP_RUN_E2E_NATIVE_CPU=1 \
./scripts/local_ci/run_ci.sh
```

---

## Timing Expectations (aarch64)

| Step | Time (approx) |
|------|---------------|
| Install LLVM via apt | 3–5 min |
| Build OCK | 10–20 min |
| Build ICD + Headers | 2–3 min |
| Download DPC++ nightly | 5–10 min |
| Build DPC++ from source | 2–4 h |
| Build SYCL-CTS (all, `-j4`) | 1–2 h |
| Run SYCL-CTS | up to 3h 30m |
| Run DPC++ e2e (OpenCL) | up to 30 min |

---

## Workspace Layout

```
~/ock_ci_workspace/
├── llvm_install -> /usr/lib/llvm-20     # LLVM symlink
├── build_ock/                           # OCK cmake build dir
├── install/                             # OCK artifact (libCL.so, clc)
│   └── lib/libCL.so
├── opencl_headers/                      # KhronosGroup/OpenCL-Headers source
├── build_opencl_headers/
├── install_opencl_headers/
├── opencl_icd/                          # KhronosGroup/OpenCL-ICD-Loader source
├── build_icd/
├── install_icd/
│   └── lib/libOpenCL.so
├── dpcpp/
│   └── aarch64-linux/install/           # DPC++ install (clang++, libsycl.so, ...)
├── llvm_dpcpp/                          # intel/llvm source (if --dpcpp-source build)
├── SYCL-CTS.src/                        # KhronosGroup/SYCL-CTS source
├── SYCL-CTS/                            # SYCL-CTS build dir
│   └── bin/                             # test binaries
├── llvm_e2e/                            # intel/llvm sparse (sycl/test-e2e only)
├── build_e2e_opencl/                    # e2e cmake build (opencl:cpu)
├── build_e2e_native_cpu/                # e2e cmake build (native_cpu:cpu)
├── sycl_cts.log / sycl_cts.fail / sycl_cts.xml
├── e2e_opencl_known_override.csv
└── e2e_native_known_override.csv
```

---

## Relationship to CI Actions

| Script step | GitHub Actions action/job |
|-------------|--------------------------|
| `step_setup_llvm` | `.github/actions/setup_build` (`llvm_source=install`) |
| `step_build_ock` | `.github/actions/do_build_ock_artefact` + `do_build_ock` |
| `step_build_icd` | `.github/actions/do_build_icd` |
| `step_build_dpcpp` | `.github/actions/do_build_dpcpp` |
| `step_build_sycl_cts` | `.github/actions/do_build_sycl_cts` |
| `run_sycl_cts` | `.github/actions/run_sycl_cts` |
| `run_sycl_e2e_opencl` | `.github/actions/do_build_run_sycl_e2e` |
| `run_sycl_e2e_native_cpu` | *(no existing CI job — native_cpu variant)* |
