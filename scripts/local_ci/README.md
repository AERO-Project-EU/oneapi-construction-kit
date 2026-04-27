# OCK Local CI — Linux ARM (aarch64)

Replicates the following GitHub Actions jobs from `run_ock_external_tests.yml` locally:

| Label | CI Job | Description |
|-------|--------|-------------|
| a) | `build_sycl_cts_aarch64` + `run_sycl_cts_aarch64` | SYCL-CTS via OpenCL (OCK as ICD) |
| b) | `run_sycl_e2e_aarch64` | DPC++ e2e via OpenCL (OCK as ICD) |
| c) | *(opt-in)* | DPC++ e2e via `native_cpu` backend (no OCK) |
| d) | *(opt-in)* | SYCL-CTS via `native_cpu` backend (no OCK) |
| e) | *(opt-in)* | OCK UnitCL — OCK's own OpenCL test suite via `ninja check-ock-UnitCL` |

---

## Quick Start

> **aarch64:** intel/llvm does not publish aarch64 nightly binaries.
> You must pass `--dpcpp-source build` (builds DPC++ from source, ~2–4 h).

```bash
# Full run on aarch64 — builds everything, then runs SYCL-CTS (a) + DPC++ e2e via OpenCL (b):
WORKSPACE=/root/ock_ci_workspace ./scripts/local_ci/run_ci.sh --dpcpp-source build

# x86_64 — can download a prebuilt nightly instead:
./scripts/local_ci/run_ci.sh

# All four test suites (a + b + c + d):
./scripts/local_ci/run_ci.sh --dpcpp-source build --all-tests

# Only SYCL-CTS via OpenCL (a):
./scripts/local_ci/run_ci.sh --dpcpp-source build --only-sycl-cts

# Only SYCL-CTS via native_cpu (d):
./scripts/local_ci/run_ci.sh --dpcpp-source build --only-sycl-cts-native

# Only DPC++ e2e via OpenCL (b):
./scripts/local_ci/run_ci.sh --dpcpp-source build --only-e2e-opencl

# Only DPC++ e2e via native_cpu (c):
./scripts/local_ci/run_ci.sh --dpcpp-source build --only-e2e-native

# Only OCK UnitCL (e) — does NOT need DPC++ or SYCL-CTS:
./scripts/local_ci/run_ci.sh --only-ock-unitcl

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

## Running unattended (SSH-safe)

The full run takes many hours. Use one of the patterns below so the job
survives an SSH disconnect.

### Option 1 — nohup (always available)

```bash
nohup bash -c '
  WORKSPACE=/root/ock_ci_workspace \
  ./scripts/local_ci/run_ci.sh \
    --dpcpp-source build \
    --all-tests \
    --log-file /root/ock_ci_workspace/ci_run.log
' &
echo "PID $!"
disown
```

Monitor progress from another shell:

```bash
tail -f /root/ock_ci_workspace/ci_run.log
```

Check whether it is still running:

```bash
ps aux | grep run_ci
```

### Option 2 — screen (reattachable session)

```bash
screen -dmS ock_ci bash -c '
  WORKSPACE=/root/ock_ci_workspace \
  ./scripts/local_ci/run_ci.sh \
    --dpcpp-source build \
    --all-tests \
    --log-file /root/ock_ci_workspace/ci_run.log
'

# Reattach at any time:
screen -r ock_ci
```

### Option 3 — tmux (reattachable session)

```bash
tmux new-session -d -s ock_ci \
  'WORKSPACE=/root/ock_ci_workspace \
   ./scripts/local_ci/run_ci.sh \
     --dpcpp-source build \
     --all-tests \
     --log-file /root/ock_ci_workspace/ci_run.log'

# Reattach at any time:
tmux attach -t ock_ci
```

### Log files written by the script

| File | Contents |
|------|----------|
| `$WORKSPACE/ci_run.log` | Full script output (when `--log-file` is used) |
| `$WORKSPACE/sycl_cts.log` | SYCL-CTS (OpenCL) results |
| `$WORKSPACE/sycl_cts.fail` | SYCL-CTS (OpenCL) failures only |
| `$WORKSPACE/sycl_cts.xml` | SYCL-CTS (OpenCL) JUnit XML |
| `$WORKSPACE/sycl_cts_native.log` | SYCL-CTS (native_cpu) results |
| `$WORKSPACE/sycl_cts_native.fail` | SYCL-CTS (native_cpu) failures only |
| `$WORKSPACE/sycl_cts_native.xml` | SYCL-CTS (native_cpu) JUnit XML |
| `$WORKSPACE/ock_unitcl.log` | OCK UnitCL (`check-ock-UnitCL`) output |

---

## Build Pipeline

Each step caches its output directory. If the target already exists, the step is
skipped (override with `--force-rebuild`).

```
Step 0   setup_deps      — apt install + pip install
Step 1   setup_llvm      — install LLVM 20 from apt.llvm.org → llvm_install/
Step 2   build_ock       — build OCK artifact (libCL.so + clc, tests=OFF) → install/
Step 3   build_icd       — OpenCL Headers + ICD Loader → install_icd/  install_opencl_headers/
Step 3b  build_ock_tests — build OCK with CA_ENABLE_TESTS=ON (UnitCL) → build_ock_tests/  (opt-in)
Step 4   build_dpcpp     — get DPC++ (download or build) → dpcpp/aarch64-linux/install/
Step 5   build_sycl_cts  — build SYCL-CTS binaries → SYCL-CTS/bin/
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

### OCK Tests Build *(step 3b, opt-in)*

A **separate build dir** (`build_ock_tests/`) is used when running OCK UnitCL (e),
so the regular artifact build (step 2) stays clean and pruned.

CMake flags used:

```cmake
-DCA_ENABLE_API=cl
-DCA_MUX_TARGETS_TO_ENABLE=host
-DCA_MUX_COMPILERS_TO_ENABLE=host
-DCA_LLVM_INSTALL_DIR=<llvm_install>
-DCMAKE_BUILD_TYPE=Release
-DCA_ENABLE_TESTS=ON                              # required for check-* targets
-DCA_CL_ENABLE_ICD_LOADER=ON
-DOCL_EXTENSION_cl_khr_command_buffer=ON
-DOCL_EXTENSION_cl_khr_command_buffer_mutable_dispatch=ON
-DOCL_EXTENSION_cl_khr_extended_async_copies=ON
```

`spirv-as` (from the `spirv-tools` apt package, already a baseline dependency) is
auto-discovered by CMake — no explicit `SpirvTools_spirv-as_EXECUTABLE` path needed.

Triggered by `--with-ock-unitcl` or `--only-ock-unitcl` (also sets `STEP_BUILD_OCK_TESTS=1`).

### DPC++

Two options controlled by `--dpcpp-source`:

| Option | Description | Arch support | Time |
|--------|-------------|--------------|------|
| `download_release` *(default)* | Downloads latest nightly tarball from `intel/llvm` GitHub releases | **x86_64 only** | ~5 min |
| `build` | Clones `intel/llvm` and builds from source | aarch64 + x86_64 | 2–4 h on ARM |

When downloading, the script tries up to 14 days back to find a published nightly.

OCK-specific patches from `scripts/testing/patches/DPCPP-*.patch` are applied
when building from source.

> **Workspace reuse across architectures:** if the `dpcpp/` directory in
> `WORKSPACE` was populated on a different host architecture (e.g. x86_64
> binaries in an aarch64 workspace), the script detects the mismatch at startup
> and automatically removes the stale install before rebuilding.

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

### a) SYCL-CTS via OpenCL

```bash
./scripts/local_ci/run_ci.sh --only-sycl-cts
# or just the run step if artifacts exist:
./scripts/local_ci/run_ci.sh --only-sycl-cts --tests-only
```

Environment:
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

Timeout: **3h 30m** (matches CI). Results: `$WORKSPACE/sycl_cts.{log,fail,xml}`

### b) DPC++ e2e via OpenCL

```bash
./scripts/local_ci/run_ci.sh --only-e2e-opencl
```

Clones `intel/llvm` (sparse: `sycl/test-e2e` only) and configures with:

```cmake
-DSYCL_TEST_E2E_TARGETS=opencl:cpu
```

`OCL_ICD_FILENAMES` is set to OCK's `libCL.so` so all OpenCL calls go through OCK's host backend.

Override/known files used:
- `scripts/testing/sycl_e2e/known.csv`
- `scripts/testing/sycl_e2e/override_all.csv`
- `scripts/testing/sycl_e2e/override_host_aarch64_linux.csv`

Timeout: **30 min** (1800 s, matches CI).

### c) DPC++ e2e via native_cpu (opt-in)

```bash
./scripts/local_ci/run_ci.sh --with-native-cpu
# or together with all tests:
./scripts/local_ci/run_ci.sh --all-tests
```

Configures the e2e suite with:

```cmake
-DSYCL_TEST_E2E_TARGETS=native_cpu:cpu
```

Uses `ONEAPI_DEVICE_SELECTOR=native_cpu:*`. Does **not** use OCK.

### d) SYCL-CTS via native_cpu (opt-in)

```bash
./scripts/local_ci/run_ci.sh --with-sycl-cts-native
# or only this suite:
./scripts/local_ci/run_ci.sh --only-sycl-cts-native
```

Runs the same SYCL-CTS binaries (built in step 5) with `ONEAPI_DEVICE_SELECTOR=native_cpu:*`
instead of `opencl:0`. Does **not** use OCK.

Environment:
```bash
ONEAPI_DEVICE_SELECTOR=native_cpu:*
LD_LIBRARY_PATH=<dpcpp>/lib
```

Timeout: **3h 30m**. Results: `$WORKSPACE/sycl_cts_native.{log,fail,xml}`

> **Note:** `c)` and `d)` are disabled by default. The override CSV files are currently
> tuned for the OpenCL path, so expect a higher unknown/fail count until
> `scripts/testing/sycl_cts/` and `scripts/testing/sycl_e2e/` are extended with
> native_cpu-specific override files.

### e) OCK UnitCL (opt-in)

```bash
./scripts/local_ci/run_ci.sh --only-ock-unitcl
# or alongside other suites:
./scripts/local_ci/run_ci.sh --with-ock-unitcl
```

Runs OCK's own OpenCL test suite (UnitCL) via `ninja check-ock-UnitCL`.
Unlike (a)–(d), this does **not** depend on DPC++ or SYCL-CTS — it tests OCK's
OpenCL implementation directly through the ICD loader. `--only-ock-unitcl`
therefore disables the DPC++ and SYCL-CTS build steps automatically.

Environment:
```bash
OCL_ICD_FILENAMES=$WORKSPACE/build_ock_tests/lib/libCL.so
LD_LIBRARY_PATH=$WORKSPACE/build_ock_tests/lib
```

Results: `$WORKSPACE/ock_unitcl.log` (full ninja + gtest output).

---

## CLI Reference

```
./scripts/local_ci/run_ci.sh [OPTIONS]

BUILD OPTIONS:
  --workspace DIR           Working dir for all artifacts  [default: ~/ock_ci_workspace]
  --llvm-version VER        LLVM major version: 20, 21     [default: 20]
  --arch ARCH               Target arch: aarch64, x86_64   [default: aarch64]
  --jobs N                  Parallel build jobs            [default: nproc]
  --dpcpp-source SRC        'download_release' or 'build'  [default: download_release]
  --force-rebuild           Rebuild artifacts even if they already exist

STEP SELECTION:
  --only-sycl-cts           Build everything + run only SYCL-CTS via OpenCL (a)
  --only-sycl-cts-native    Build everything + run only SYCL-CTS via native_cpu (d)
  --only-e2e-opencl         Build everything + run only DPC++ e2e via OpenCL (b)
  --only-e2e-native         Build everything + run only DPC++ e2e via native_cpu (c)
  --only-ock-unitcl         Build OCK with tests + run only OCK UnitCL (e)
  --all-tests               Run all four SYCL test suites (a + b + c + d, excludes UnitCL)
  --tests-only              Skip all build steps, only run tests
  --skip-llvm               Skip LLVM installation step
  --skip-ock-build          Skip OCK build step
  --skip-dpcpp              Skip DPC++ build step
  --with-native-cpu         Also run DPC++ e2e via native_cpu (c)
  --with-sycl-cts-native    Also run SYCL-CTS via native_cpu (d)
  --with-ock-unitcl         Also build OCK tests + run OCK UnitCL (e)
  --no-sycl-cts             Disable SYCL-CTS via OpenCL run
  --no-e2e-opencl           Disable DPC++ e2e via OpenCL run
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
| Download DPC++ nightly *(x86_64 only)* | 5–10 min |
| Build DPC++ from source *(required for aarch64)* | 2–4 h |
| Build SYCL-CTS (all, `-j4`) | 1–2 h |
| Run SYCL-CTS | up to 3h 30m |
| Run DPC++ e2e (OpenCL) | up to 30 min |
| Build OCK tests build (3b) | 15–30 min |
| Run OCK UnitCL (e) | 10–30 min |

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
├── build_ock_tests/                     # OCK build with tests=ON (UnitCL)
│   └── bin/UnitCL                       # OCK's OpenCL test binary
├── sycl_cts.log / sycl_cts.fail / sycl_cts.xml
├── ock_unitcl.log
├── e2e_opencl_known_override.csv
└── e2e_native_known_override.csv
```

---

## Troubleshooting

### `clang++` not found after `--dpcpp-source build`

When building DPC++ from source, `buildbot/compile.py` installs into
`llvm_dpcpp/build/<arch>-linux/install/` inside the workspace. The script
creates a symlink from the canonical `dpcpp/<arch>-linux/install/` path to that
location automatically. If the symlink is missing (e.g. from an interrupted
earlier run before the fix), create it manually:

```bash
ln -s /root/ock_ci_workspace/llvm_dpcpp/build/aarch64-linux/install \
      /root/ock_ci_workspace/dpcpp/aarch64-linux/install
```

Then resume without re-running the completed build steps:

```bash
WORKSPACE=/root/ock_ci_workspace \
  STEP_SETUP_DEPS=0 STEP_SETUP_LLVM=0 STEP_BUILD_OCK=0 STEP_BUILD_ICD=0 STEP_BUILD_DPCPP=0 \
  ./scripts/local_ci/run_ci.sh --dpcpp-source build
```

### `Exec format error` for `clang++` (wrong architecture)

If the workspace was previously used on a different host architecture, the
cached `clang++` binary will be the wrong ELF type. The script now detects this
and removes the stale install automatically. If you hit this on an older version
of the script, remove it manually:

```bash
rm -rf /root/ock_ci_workspace/dpcpp/aarch64-linux/install
```

Then re-run with `--dpcpp-source build`.

### SYCL-CTS patch fails to apply

If a patch was partially applied during a previous interrupted run, `git apply`
will fail on the next attempt. The script now detects already-applied patches
and skips them, and falls back to `--3way` if upstream context lines have
drifted. If you hit this on an older version, reset the source tree:

```bash
git -C /root/ock_ci_workspace/SYCL-CTS.src checkout -- .
```

---

## Relationship to CI Actions

| Script step | GitHub Actions action/job |
|-------------|--------------------------|
| `step_setup_llvm` | `.github/actions/setup_build` (`llvm_source=install`) |
| `step_build_ock` | `.github/actions/do_build_ock_artefact` + `do_build_ock` |
| `step_build_icd` | `.github/actions/do_build_icd` |
| `step_build_ock_tests` (3b) | *(no existing external-CI job — local-only, tests=ON build for UnitCL)* |
| `step_build_dpcpp` | `.github/actions/do_build_dpcpp` |
| `step_build_sycl_cts` | `.github/actions/do_build_sycl_cts` |
| `run_sycl_cts` (a) | `.github/actions/run_sycl_cts` |
| `run_sycl_e2e_opencl` (b) | `.github/actions/do_build_run_sycl_e2e` |
| `run_sycl_e2e_native_cpu` (c) | *(no existing CI job — native_cpu e2e variant)* |
| `run_sycl_cts_native_cpu` (d) | *(no existing CI job — native_cpu SYCL-CTS variant)* |
| `run_ock_unitcl` (e) | *(no external-CI job — internal `check-ock-UnitCL` target)* |
