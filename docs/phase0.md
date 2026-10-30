# grbl-p2: Phase 0 deliverables (repo, toolchain, CI)

This directory is laid out as an **overlay for the root of the `grbl-p2` fork**
(forked from gnea/grbl). Everything except this README goes into the fork at the
same path. This README should be committed as `docs/phase0.md`: the fork root
already has GRBL's own `README.md`, and `.gitignore` here is upstream's file with
lines appended.

```
.github/workflows/p2-build.yml   CI: pinned flexspin (cached), build grbl_p2.binary, artifact, size report
tools/flexspin.version           pin: spin2cpp tag v7.7.3, commit eb2639617bf6cc25f55a34d8285af39d233adf81
tools/build_flexspin.sh          clone pinned tag, verify SHA, make, install to tools/.flexspin, smoke test; idempotent
tools/build_grbl_p2.sh           stage grbl/ sources, apply patches/, compile with flexspin, print size report
patches/0001-flexc-compat-vla-and-nested-designators.diff   fixes 2+3 (settings.c, print.c)
p2/stub/                         fixes 4+5: fake <avr/*.h>, <util/delay.h>, fakeregs.c, trunc() (temporary, Phase 2 removes)
docs/phase0-fixes.md             the 5 source fixes: what, why, where, caveats, how Phase 1 absorbs them
docs/ref/README.md               reference docs: decision, usage, pinning policy, fetch results
docs/ref/manifest.tsv            reference docs list: id, kind, dest, sha256 (or -), version, licence, title, URLs
tools/fetch_ref_docs.sh          download the manifest into git-ignored docs/ref/vendor/; verifies pinned sha256; idempotent
.gitignore                       upstream .gitignore + /build/p2/, /tools/.flexspin/, /tools/.cache/, /docs/ref/vendor/
```

## Applying to the fork

Either copy the files: `rsync -a --exclude README.md --exclude tools/.flexspin --exclude tools/.cache --exclude docs/ref/vendor phase0/ <fork>/`
and then `cp phase0/README.md <fork>/docs/phase0.md`. Or, from the fork root, run
`git apply /workspace/grbl_propeller/phase0_overlay_for_fork.patch`. That file
contains the same changes as a single diff against gnea/grbl master `bfb67f0`
(the README already moved to `docs/phase0.md`), and it applies cleanly to an
upstream clone. Commit on a branch such as `phase0-toolchain-ci` and open the PR.

## Run locally (Linux)

Prerequisites: `git`, `make`, `bison`, `gcc`. On Debian/Ubuntu:
`sudo apt-get install build-essential bison git`.

```bash
tools/build_flexspin.sh            # under a minute the first time; a no-op afterwards (stamp file)
tools/build_grbl_p2.sh             # -> build/p2/grbl_p2.binary + size report
# options: --src DIR (default ./grbl), --out DIR (default ./build/p2),
#          FLEXSPIN=/path/to/flexspin, FLEXSPIN_PREFIX=... for the toolchain install dir
```

Reference docs (optional for the build, recommended before Phase 1/4 work):
`tools/fetch_ref_docs.sh` (needs `curl`). See `docs/ref/README.md`.

The build never edits `grbl/`. It copies the sources to `build/p2/src/`, applies
`patches/*.diff` there (and skips any patch that is already present upstream,
so it keeps working once Phase 1 commits the fixes), and adds `p2/stub/`.

Flags (identical to the proposal's measured build):
`flexspin -2 -O2 -I p2/stub -D__flash= -DF_CPU=16000000 -DM_PI=3.14159265358979323846 -o grbl_p2.binary *.c`

## Verified on this machine (2026-10-29)

* `tools/build_flexspin.sh` cloned spin2cpp `v7.7.3`, verified HEAD =
  `eb2639617bf6cc25f55a34d8285af39d233adf81`, built and installed it, and the
  smoke test passed. `flexspin --version` reports `Version 7.7.3-HEAD-v7.7.3`.
  Running it again printed "up to date" without rebuilding.
* `tools/build_grbl_p2.sh` on pristine gnea/grbl (master `bfb67f0`) printed:

```
==== grbl_p2.binary size report ====
flexspin:        Version 7.7.3-HEAD-v7.7.3 Compiled on: Oct 29 2026
flags:           -2 -O2 -I .../p2/stub -D__flash= -DF_CPU=16000000 -DM_PI=3.14159265358979323846
image:           50488 bytes (49.30 KB)
flexspin says:   50488 bytes
P2 hub RAM:      524288 bytes (512 KB)
hub used:        9.63 %
hub free:        473800 bytes (462.70 KB) before runtime buffers/stacks
warning lines:   51
sha256:          251ab68b6370f981ac0a36b736830f6c539318906195894aa61ada09f9d802db
====================================
```

  The output is reproducible: the same sha256 came out on repeated builds, and
  also from a mock fork made by overlaying these files on an upstream clone.
  It also builds from the already-patched test tree, where the patch is
  detected and skipped.
* The same flags with the proposal's flexspin 7.8.0-beta rebuild the test tree
  **byte-identical** to the proposal's 52,948-byte image. The pinned stable
  7.7.3 produces 2,460 bytes less.
* The workflow passes `actionlint` 1.7.12 (with shellcheck 0.11.0) and loads
  with PyYAML. `shellcheck -x tools/*.sh` is clean. I also ran the workflow's
  shell steps locally with `GITHUB_STEP_SUMMARY`/`GITHUB_OUTPUT` set, and the
  markdown size table was written correctly.

## Mapping to Phase 0 acceptance criteria (proposal §4)

| Criterion | Delivered by |
|---|---|
| **CI green** | `.github/workflows/p2-build.yml` job `p2-build` on push, pull_request, workflow_dispatch (ubuntu-24.04). The job fails if flexspin fails to build, the SHA doesn't match the pin, the compile fails, the binary is missing or empty, or the image is larger than 512 KB. |
| **Artifact `grbl_p2.binary` produced** | `actions/upload-artifact@v4`, artifact name `grbl_p2.binary`, `if-no-files-found: error`. Logs and size reports go to a second artifact, `grbl_p2-build-logs`. |
| **Size printed in CI log** | `tools/build_grbl_p2.sh` prints the report to the log, appends a markdown table to `$GITHUB_STEP_SUMMARY`, and the workflow adds a `::notice` annotation with the byte count. |
| Pinned toolchain | `tools/flexspin.version` (tag and commit SHA, checked on every build). The CI cache key includes the SHA and the hash of the build script. |
| Vendored reference docs | `docs/ref/manifest.tsv` + `tools/fetch_ref_docs.sh` → git-ignored `docs/ref/vendor/` (decided: nothing from Parallax is committed). 13/14 fetched locally; see `docs/ref/README.md` |

## Agreed decisions for Phase 0

* **CI is P2-only in Phase 0 (agreed).** §4 Phase 0 also lists "builds the host
  binary, and runs tests". These are **deferred to Phases 2–3**, where the host
  HAL (Phase 2) and the test harness (Phase 3) come in. At that point a
  `host-build`/`test` job gets added to the workflow. Until then the Phase 0
  gate is: pinned flexspin builds, `grbl_p2.binary` is produced and uploaded,
  and its size is printed.
* **Reference docs: manifest + fetch script (agreed).** Nothing from Parallax is
  committed. `docs/ref/manifest.tsv` lists the sources, `tools/fetch_ref_docs.sh`
  downloads them into git-ignored `docs/ref/vendor/`, and sha256 is pinned
  wherever it can be verified (currently the flexspin docs). CI doesn't run
  the fetch.
* **Clock 160 → 180 MHz is deferred to Phase 1 (agreed).** See `docs/phase0-fixes.md`.
* **Pin:** the proposal measured 7.8.0-beta (spin2cpp master `a7a4136`). Phase 0
  pins the latest **stable** release, v7.7.3 (2026-09-20), as the brief asked.
  The image is 50,488 B instead of 52,948 B. Bump the pin later if a 7.8.x fix
  turns out to matter.

## Open items

* The Phase 0 image is a **compile/size proof only** (fake registers, 160 MHz
  default clock). It is not something to flash.
* The PASM2 Manual (2022-11-01) can't be fetched by script (forums.parallax.com
  serves a captcha). Download it by hand into `docs/ref/vendor/p2/`. Someone with
  a browser also needs to find the P2-EC Rev D schematic URL.
* Not verifiable without GitHub: whether `ubuntu-24.04` already ships bison
  (the job installs it only when it's missing), cache save/restore behaviour,
  artifact upload, step-summary rendering, and whether the fork's Actions
  settings allow third-party `actions/*@v4`. Consider pinning those actions to
  commit SHAs once the repo exists.
