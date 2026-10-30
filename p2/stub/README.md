# p2/stub: temporary AVR stand-ins for the Phase 0 build

These files let the unmodified GRBL core compile with flexspin for the P2. They
are **not a HAL**: every AVR register becomes a dummy variable in `fakeregs.c`.
They are copied unchanged from the test build that the proposal's size numbers
came from. Phase 2 replaces them with `hal/` (avr/host/p2 backends) and deletes
this directory. See `docs/phase0-fixes.md` for what each piece covers.

| File | Provides |
|---|---|
| `avr/io.h` | register/bit names mapped onto `FAKEREG[]` / `FAKEREG16[]`; `_BV`, `bit_is_set`, ...; `trunc()` macro |
| `avr/interrupt.h` | `ISR(v)` as a plain function; `sei()`/`cli()` as no-ops |
| `avr/pgmspace.h` | `PSTR`, `PROGMEM`, `pgm_read_byte*` as identity macros (hub RAM is flat) |
| `avr/wdt.h` | `wdt_reset()` no-op |
| `util/delay.h` | `_delay_ms`/`_delay_us` no-ops |
| `fakeregs.c` | storage for the fake registers |
