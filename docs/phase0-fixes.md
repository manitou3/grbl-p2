# Phase 0: source fixes needed for the flexspin P2 build

Phase 0's acceptance criterion is "CI green, `grbl_p2.binary` produced, size
printed". Unmodified gnea/grbl does **not** compile with flexspin, so CI needs
the five small fixes found while measuring for the proposal (Section 1). Phase 0
keeps `grbl/` byte-identical to upstream: `tools/build_grbl_p2.sh` copies the
sources into `build/p2/src/` and applies the fixes there. Phase 1 is where
they get committed properly, with a justification for each one.

Upstream base used for verification: gnea/grbl `master` @ `bfb67f0c7963fe3ce4aaf8a97f9009ea5a8db36e`
("Update README.md"). This is the tip of master after tag `v1.1h.20190825`. Re-check
the patch against whatever commit the fork actually starts from.

| # | Problem under FlexC | Where | Phase 0 fix | Mechanism |
|---|---|---|---|---|
| 1 | `__flash` (avr-gcc named address space) is unknown | `grbl/settings.c:26` `const __flash settings_t defaults` | define it away | build flag `-D__flash=` |
| 2 | Nested designated initializers (`.steps_per_mm[X_AXIS] = ...`) are unsupported | `grbl/settings.c` `defaults` initializer | rewrite as `.steps_per_mm = {X, Y, Z}` etc. (same values, same order) | `patches/0001-flexc-compat-vla-and-nested-designators.diff` |
| 3 | Variable-length array `unsigned char buf[digits]` | `grbl/print.c` `print_uint8_base2_ndigit()` | fixed `buf[8]` (a `uint8_t` has at most 8 binary digits; the function has no callers in upstream 1.1h, only its prototype in `print.h`) | same patch |
| 4 | `trunc()` missing from the FlexC math library | used in `grbl/*.c` float code | `#define trunc(x) ((float)(long)(x))` in the stub `<avr/io.h>` | `p2/stub/avr/io.h` |
| 5 | AVR registers and bit names (`PORTB`, `TCCR1B`, `OCIE1A`, `UDR0`, ...), `<avr/interrupt.h>`, `<avr/pgmspace.h>`, `<avr/wdt.h>`, `<util/delay.h>` | `cpu_map.h`, `stepper.c`, `serial.c`, `limits.c`, `eeprom.c`, ... | stub headers that map every register to a dummy `volatile` byte/word in `fakeregs.c`; `ISR()`, `sei()`, `cli()`, `PSTR`, `PROGMEM`, `pgm_read_byte*`, `_delay_*` become no-op or identity macros | `p2/stub/` (include path `-I p2/stub`, plus `fakeregs.c` compiled in) |

Two more defines that avr-gcc/avr-libc normally provide also go on the command line:
`-DF_CPU=16000000` (used by `stepper.c`) and `-DM_PI=3.14159265358979323846` (used by
`motion_control.c`). They are not counted among the five fixes.

With these, and the flags above, the pre-proposal test tree rebuilds
**byte-for-byte identical** to the proposal's measured 52,948-byte image when
built with flexspin 7.8.0-beta (spin2cpp master `a7a4136`). With the pinned stable
**flexspin v7.7.3** the same sources give **50,488 bytes**.

## Caveats to address in Phase 1/2 (not needed for green CI)

* **The image does nothing useful on hardware.** The registers are fake, so this
  build only proves that the core compiles and shows how big it is. The real
  HAL comes in Phase 2.
* `trunc` macro: `(float)(long)x` truncates toward zero, as `trunc` should. It
  is wrong for |x| >= 2^31, and it takes and returns `float` rather than `double`.
  Phase 1 should check it against GCC as the proposal asks, or replace it with
  `truncf` once FlexC has it.
* The `print.c` fix assumes `digits <= 8`. Phase 1 should clamp `digits` to 8
  (or delete the unused function).
* flexspin prints 34 harmless "macro is redefined" warnings: GRBL's
  `nuts_bolts.h` redefines `true`/`false` after FlexC's `<stdbool.h>`. Phase 1's
  "no new warnings" gate should either baseline these or guard the defines with `#ifndef`.
* **Clock: 160 → 180 MHz, deferred to Phase 1 (decision).** The Phase 0 image
  runs at flexspin's default 160 MHz (`_clkfreq = 160000000`), and the proposal
  targets 180 MHz. Phase 0 leaves it alone on purpose, because changing it doesn't
  affect "CI green / binary / size" and the fake-register image never runs on
  hardware. Phase 1 sets it explicitly. Per FlexC `doc/c.md` at the pinned
  v7.7.3 (`docs/ref/vendor/flexspin/c.md`, "_clkfreq"), that means
  `enum { _clkfreq = 180000000 };` in the top-level file next to `main()`
  (add `_xtlfreq` if the board crystal isn't the default), or a runtime
  `_clkset(mode, freq)`. Phase 1 should also confirm the value in the startup
  log and record it as fix #6. The F_CPU=16000000 define is a separate AVR
  leftover that the Phase 2 HAL removes.

## Applying on the fork

* **Phase 0 (as delivered):** commit `patches/` and `p2/stub/` and leave `grbl/`
  alone. The build script applies the patch to its staging copy.
* **Phase 1:** `git apply patches/0001-flexc-compat-vla-and-nested-designators.diff`
  at the repo root, commit it, then delete the patch (or leave it in place:
  the build script spots that it is already applied and skips it).
