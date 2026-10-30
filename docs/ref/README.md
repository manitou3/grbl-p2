# docs/ref: reference documentation (manifest + fetch, nothing vendored in git)

**Purpose (proposal §4, Phase 0):** give the agent local copies of the P2,
PASM2, smart pin and FlexC documentation, so it can check instructions, flags,
smart-pin modes and FlexC dialect limits against real text instead of memory.
This matters most in Phase 1 (FlexC dialect), Phase 4 (PASM2 step executor),
Phase 5 (smart-pin UART) and Phase 7 (smart-pin PWM).

## Decision (Phase 0): manifest + fetch script, no committed copies

The Parallax documents are copyrighted. The PDFs say duplication is allowed for
educational use only, not commercial use, and the Google Docs state no licence.
So **nothing from Parallax gets committed.** The repo contains only:

| File | Committed? | What |
|---|---|---|
| `docs/ref/manifest.tsv` | yes | one row per document: id, kind, dest path, expected sha256 (or `-`), version/date, licence note, title, source URL(s) |
| `tools/fetch_ref_docs.sh` | yes | downloads everything in the manifest into `docs/ref/vendor/` |
| `docs/ref/vendor/` | **no** (git-ignored) | the downloaded files, plus `FETCHED.tsv` (what was fetched, from where, observed sha256, time UTC) |

For consistency the MIT-licensed flexspin docs are fetched the same way (pinned
to the compiler commit) rather than committed.

## Usage

```bash
tools/fetch_ref_docs.sh               # fetch what's missing; safe to re-run (idempotent)
tools/fetch_ref_docs.sh --refresh     # also re-download unpinned (live) documents
tools/fetch_ref_docs.sh --check       # offline: verify vendor/ against the manifest
tools/fetch_ref_docs.sh --only p2-datasheet --strict
```

* Each URL in a row is tried in order. A download only counts if it returns
  HTTP 200 **and** has the right magic bytes (`%PDF`, `PK` for docx/xlsx, and
  not HTML for text/csv). That rejects the 404, captcha and "access denied"
  pages that parallax.com, forums.parallax.com and Mouser serve to scripts.
* A **download failure** is a warning: it is listed in the summary and the
  script still exits 0, unless you pass `--strict`. Fetch such a file by hand in a
  browser and save it at the row's `dest` path; later runs keep it.
* A **sha256 mismatch** on a pinned row is always an error (exit 1), and the
  existing good file is left alone.
* Files are written atomically (temp file, then `mv`), so an interrupted run
  never leaves a half-written file in place.

## Pinning policy

* `sha256` is only filled in where it can be **verified against an
  authoritative source**. Currently those are the four spin2cpp files, checked
  against the local git checkout of the pinned commit `eb26396` (v7.7.3).
  When `tools/flexspin.version` is bumped, update those rows (commit in the URL
  and sha256) in the same commit.
* Parallax rows are `-`. The Google Docs/Sheets are live documents with no
  stable bytes, and the PDF copies come from distributors or mirrors that
  haven't been checked against a copy from parallax.com. `FETCHED.tsv` records
  the observed hash. Once someone has compared a file with the official
  download, that hash can be copied into the manifest.

## Documents (manifest ids)

| id | Document | Version | Needed for |
|---|---|---|---|
| `p2-silicon-doc-txt` / `-pdf` | P2 Silicon Documentation (Chip Gracey): cogs, hub, CORDIC, events, interrupts, smart pin modes | v35 2021-05-18 (Rev B/C) | Ph 4, 5, 7 |
| `p2-pasm2-instructions-csv` / `-xlsx` | PASM2 instruction list: encodings, clocks, C/Z | v35 sheet (CSV = first tab, XLSX = all tabs) | Ph 4 |
| `p2-smartpins-supplement` | Smart Pin Supplementary Documentation (Jon Titus), docx | "rev 5" | Ph 5, 7 |
| `p2-pasm2-manual` | PASM2 Manual | 2022-11-01 | Ph 4 |
| `p2-hardware-manual` | P2X8C4M64P Hardware Manual | 2022-11-01 | Ph 2, 8 |
| `p2-datasheet` | P2X8C4M64P Datasheet | 2022-11-01 | Ph 8 |
| `p2-edge-product-guide` | P2 Edge Module (P2-EC) Product Guide | v1.0 2020-11-12 | Ph 6 |
| `p2-edge-schematic-reva` | P2-EC schematic | Rev A | Ph 6 (flash/microSD pin sharing, Appendix B) |
| `flexc-c-md`, `flexspin-general-md`, `flexspin-pasm-code-md`, `flexspin-licence` | FlexC/flexspin docs at the pinned compiler commit | v7.7.3 @ `eb26396` (sha256 pinned) | Ph 1, 4 |

Not in the manifest on purpose:
* **FlexC headers** (`propeller2.h`, `sys/p2es_clock.h`, libc): use the installed
  copies in `tools/.flexspin/include/`.
* **GRBL docs**: already in the fork (`doc/markdown/`, `doc/csv/`, GPLv3).
* The **GRBL wiki**: add rows if Phases 3 and 5 need it.
* **p2docs.github.io** mirror: no licence on its repo (checked 2026-10-29).
  It's fine for reading in a browser, but it isn't a source here.

## Local fetch result (2026-10-29)

13 of 14 fetched. All 4 pinned sha256 values matched. A second run was a no-op
(13 cached), and `--check` passed.

| id | Result |
|---|---|
| `p2-pasm2-manual` | **failed**: forums.parallax.com returns HTTP 202 with a captcha page. No other public source found. Download it by hand. |
| `p2-datasheet` | OK from the 2nd URL (robotshop CDN). The Mouser URL broke the connection (HTTP/2 INTERNAL_ERROR). |
| `p2-edge-product-guide` | OK from the 2nd URL (elmicro). Mouser failed the same way. |
| `p2-hardware-manual` | OK from a third-party mirror (docs.alexrp.com). parallax.com `/package/...` pages return 404. |
| all Google Docs/Sheets/Drive rows, elmicro schematic, spin2cpp rows | OK on the first URL |

## Open items

* The PASM2 Manual needs a manual download (see above).
* The P2-EC **Rev D** schematic and the current product guide: the parallax.com
  product/download pages can't be fetched by scripts (404/blocked). Someone
  with a browser should get the Rev D URLs, and should check whether the board
  in use is Rev D, before Phase 6.
* Optional weekly CI job (`schedule:`): run `tools/fetch_ref_docs.sh` and then
  `--check`, and report drift of the live Google Docs by comparing `FETCHED.tsv`
  hashes. This isn't in the Phase 0 workflow.
