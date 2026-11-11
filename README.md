# neo-m9n-nv

A driver for the NEO-M9N, a GNSS receiver module from u-blox, and for the
NEO-M8N as the second part of the family.  The NEO-M9N is specified in the
interface description of its firmware, "u-blox M9 SPG 4.04 Interface
description", UBX-21022436 R02, June 2023, which names the NEO-M9N-00B as a
product it applies to (the NEO-M9N's own interface description is
UBX-19035940; its PDF could not be fetched, so the facts here are from the
SPG 4.04 document of the same firmware).  The NEO-M8N is specified in "u-blox 8
/ u-blox M8 Receiver Description Including Protocol Specification",
UBX-13003221 R15
([u-blox.com/en/product/neo-m9n-module](https://www.u-blox.com/en/product/neo-m9n-module)).
The driver implements the `Gnss` and `Identifiable` traits of
[devices-nv](https://novo-lang.org/packages/devices-nv) over embedded-hal-nv's
`UartRx` and `UartTx`: the latest fix of the receiver, a fix that has completed
since the last look, the navigation rate, and the protocol version as the
identity.  It also reads the receiver on its I2C (DDC) port, and `GnssAsync` is
implemented for a host scheduler.

**Hardware: NOT VERIFIED.**  No board carries a NEO-M9N or a NEO-M8N yet.  The
device program below builds for the nRF52840 DK and the nRF54LM20 DK.  The
driver's functions run over doubles of the receiver's line that play back the
frames of the u-blox documents and a UBX-NAV-PVT frame derived by hand.  A fix
from a receiver on a board has not been read.

## Install

```sh
novo pkg add neo-m9n-nv
```

The device program is `examples/position_log.nv`.  Make it the `main` of a
package that depends on this one and build it for a board; the receiver is read
on the board's UART, which is the console its log uses, and with
`--hci-uart=physical` that is the UART itself:

```sh
novo build --target=nrf52840-dk --hci-uart=physical src/main.nv
novo build --target=nrf54lm20-dk --hci-uart=physical src/main.nv
```

## The device program

`examples/position_log.nv` opens the line to a receiver at 9600 baud, its
power-on rate, switches UBX-NAV-PVT output on, reads the protocol version, and
prints a line for each new fix:

```
gnss kind=3 lat=481373000 lon=115760000 alt=515000 sats=12
```

The latitude and longitude are in 1e-7 degrees and the altitude in millimetres
above mean sea level.  The receiver's TXD goes to the board's UART receive pin
and its RXD to the transmit pin.

```novo norun:needs-pkg
use embedded_hal.{ BoardUart }
use dev_gnss.{ Gnss }
use neo
use neo.{ Neo }

@tier(embedded)
fn main() [hw, mutate]
    let rx = Neo.attach(BoardUart { id: 0 }, neo.MODEL_M9N)
    if not rx.begin(9600)
        hal.uart.write("neo: no answer\n")
        return
    loop
        match rx.gnss_fix_new()
            Some(f) =>
                hal.uart.write(str.from_int(f.lat_e7))
                hal.uart.write("\n")
            None => ()
        hal.timer.delay_ms(100)
```

`begin` opens the line, asks for UBX-NAV-PVT once a navigation epoch on UART 1
and waits up to a second for each acknowledge, then polls UBX-MON-VER and waits
up to a second for the protocol version.  It answers `false` for a receiver that
does not answer, one that refuses a command, and one that names no version.
`gnss_fix_new` reads what has arrived on the line and answers a fix once.  The
full program is `examples/position_log.nv`.  A script builds it for the boards
below by making it the `main` of a scratch package that depends on this one.  It
also runs the emulated board's image under QEMU, where no receiver sends a byte,
and checks that the program reports it.

```sh
bash tests/device_build.sh
```

| Image | Flash | Of which the program | RAM (`.data` and `.bss`) |
|---|---|---|---|
| `nrf52840-dk`, RTT | 17,548 B | 9,354 B | 3,428 B |
| `nrf54lm20-dk`, RTT | 18,436 B | 9,418 B | 3,412 B |
| `nrf52840-dk`, `--hci-uart=physical` | 18,764 B | 10,400 B | 3,504 B |
| `nrf54lm20-dk`, `--hci-uart=physical` | 19,924 B | 10,720 B | 3,488 B |

The numbers are from the build's memory report.  Flash also holds the runtime,
the compiler's support library and the program's tables.  The arena, 65,536 B on
the Nordic boards, is the runtime's heap and is reserved whether or not the
program uses it.  760 bytes of the RAM are the driver's one stream of bytes (the
two readers and the latest fix).  The RTT rows are the image with the receiver's
line absent; the UART rows have the line.  A reply from a receiver over a DK's
UART is NOT VERIFIED until the driver rig carries one.

### The effects

Every function of the driver that reaches the UART or the timer declares `[hw]`,
and the functions and trait methods that touch the shared stream declare
`[mutate]`.  The frame builders, the checksum, the readers and the conversion of
a UBX-NAV-PVT to a fix are pure.  The driver performs no input or output of its
own and builds no list of its own: every frame is a `Vec[u8; 40]` and the
readers' buffers are `Vec`s inside their `@value` structs.  The package checks
at the embedded tier, so a program of any tier may call it.  The program above
declares `[hw, mutate]` for the same reason.

## What it is

A receiver listens to the satellites above it and reports where it is, at its
navigation rate, as a stream of bytes on a serial line.  It speaks two
protocols on the same line.  NMEA is text, on at power-up: `$GNGGA,...*76`.  UBX
is binary, which u-blox receivers prefer for a fix, because one UBX-NAV-PVT
message carries the time, the position, the velocity and the accuracy.

| Part | Protocol | Configuration |
|---|---|---|
| NEO-M9N | UBX protocol 32.01 (SPG 4.04) | UBX-CFG-VALSET and UBX-CFG-VALGET with 32-bit key IDs |
| NEO-M8N | UBX protocol 18 to 23.01 | UBX-CFG-MSG, UBX-CFG-RATE and UBX-CFG-PRT |

A UBX frame is `0xB5 0x62`, a class, an identifier, a 16-bit little-endian
length, the payload and two checksum bytes.  The checksum is the 8-bit Fletcher
algorithm over everything between the sync bytes and the checksum: CK_A = CK_A +
byte and CK_B = CK_B + CK_A, both from 0.  The documents' example is the
acknowledge of a UBX-CFG-MSG, `B5 62 05 01 02 00 06 01 0F 38`.

| UBX-NAV-PVT field | Offset | Becomes |
|---|---|---|
| year, month, day, hour, min, sec | 4 to 10 | `time`, zero unless `validDate` and `validTime` are set; a second of 60 is 59 |
| nano | 16 | `millis`; a negative `nano` borrows a second and gives 1000 plus `nano` / 1e6 |
| fixType, flags (gnssFixOK), flags3 (invalidLlh) | 20, 21, 78 | `kind`: 2 is `Fix2d`, 3 and 4 `Fix3d`, 1 `FixDeadReckoning`, 5 `FixTimeOnly`, anything else, and a fix whose gnssFixOK is clear, `FixNone` |
| numSV | 23 | `sats_used` and `sats_in_view` (NAV-SAT is not parsed) |
| lon, lat | 24, 28 | `lon_e7`, `lat_e7`, in 1e-7 degrees, 0 unless the kind has a position |
| hMSL | 36 | `alt_mm`, the height above mean sea level |
| gSpeed | 60 | `speed_mm_s`, never negative |
| headMot | 64 | `course_mdeg`: the heading of motion in 1e-5 degrees over 100, 0 to 359999 |

The frame decodes to a `UbxPvt` with all of the fields, which also holds the
accuracies (`hAcc`, `vAcc`, `sAcc`, `headAcc`), the velocities (`velN`, `velE`,
`velD`), the time accuracy and `pDOP`.

The M9's configuration keys the driver uses are in `ubx`: `KEY_RATE_MEAS`
(0x30210001, the milliseconds between measurements, at least 25),
`KEY_MSGOUT_PVT_UART1` (0x20910007, the output rate of UBX-NAV-PVT on UART 1),
`KEY_UART1OUT_UBX` (0x10740001) and `KEY_UART1OUT_NMEA` (0x10740002), the output
protocols of UART 1, `KEY_UART1_BAUD` (0x40520001), and for the DDC
`KEY_I2COUT_UBX` and `KEY_MSGOUT_PVT_I2C`.  The M8's UBX-CFG-MSG takes a class, an
identifier and a rate; UBX-CFG-RATE a measurement period of at least 50 ms in
the driver (Zephyr's limit) and a navigation rate; UBX-CFG-PRT a port, a mode
(0x8C0 is 8 data bits, no parity, one stop bit), a baud rate and the protocol
masks.

## What the package contains

| Module | What is in it |
|---|---|
| `ubx` | The UBX frame, the checksum, `UbxReader`, the frame builders, UBX-NAV-PVT as `UbxPvt` and as a fix, the acknowledges and UBX-MON-VER's protocol version |
| `nmea` | `NmeaReader`: GGA and RMC with the NMEA checksum, and the fix they make |
| `neo` | `NeoCore`, the stream of bytes; `NeoPort`, the line; the commands; the types `Neo` and `NeoUart`; the `Gnss` and `Identifiable` implementations |
| `neo_ddc` | The receiver on its DDC (I2C) port |
| `neo_async` | `NeoAsync`, the awaitable fix for a host scheduler |

## How to choose an entry point

A program on a board uses `Neo`, built by `attach` with the board's UART and the
model.  The type implements `Gnss` and `Identifiable`.

| Method | What it does |
|---|---|
| `attach(uart, model)` | the receiver, `MODEL_M9N` or `MODEL_M8N`; nothing is sent |
| `begin(baud)` | opens the line, switches UBX-NAV-PVT output on, reads the protocol version |
| `gnss_fix()` | `Gnss`: the latest fix, after reading what waits on the line; `None` before the first |
| `gnss_fix_new()` | `Gnss`: a fix that completed since the last call to either, or `None` |
| `gnss_set_rate_mhz(mhz)` | `Gnss`: the navigation rate, to the nearest at or below `mhz` millihertz; the rate taken, or 0 |
| `device_id()` | `Identifiable`: the protocol version, `who` 32 and `rev` 1 for the M9's 32.01 |
| `set_baud(baud)`, `set_nmea_off(baud)` | the receiver's UART 1 rate, and UBX alone as its output |
| `poll()`, `protocol_version()`, `bad_frames()`, `pvt_frames()` | read the line into the stream; the version `begin` named; counts |

A trait method gets a plain `self`, so a driver keeps no state between calls.
The stream's state, the two readers and the latest fix, is therefore one
module-level `NeoCore` that the methods use: one receiver per program.  A
program with two receivers, or a test, calls the functions of `neo` with a
`NeoCore` of its own: `neo.pump(port, var core, max)`, `neo.feed(var core, byte)`,
`neo.take_new_fix(var core)`, `neo.enable_pvt(port, var core, model)`.  They take
a `NeoPort` over the line.

### The DDC form

A receiver on its I2C port is at 0x42.  It has three registers: the number of
bytes waiting in its stream at 0xFD (high byte) and 0xFE, and the stream at 0xFF.
A read of the stream returns 0xFF when there is nothing, which is also a byte a
UBX payload may hold, so `ddc_available` reads the count and `ddc_pump` reads
that many bytes at most, 32 to a transaction, into a `NeoCore`.  `ddc_send`
writes a frame as one I2C write with no register address.  The form does not
implement `Gnss`, whose transport is a UART: a program calls `ddc_pump` and then
`neo.take_fix`.

### The awaitable form

`neo_async.NeoAsync` holds the board's `UartRxAsync` and implements `GnssAsync`:
`gnss_next` reads the line a byte at a time, parks the task while it is quiet,
and answers the fix a byte completes.  An `async fn` cannot take a `@value`
struct (E2015) and is refused at the embedded tier, so the type is a plain
struct and its method is `@tier(app)`; a device program polls `gnss_fix_new`.

## The rules a user needs

1. The line is 8N1 at the receiver's rate, 9600 baud at power-up.  `begin(baud)`
   sets the host's UART; it does not change the receiver's.  `set_baud` does the
   receiver first and the host after a second, and leaves the host alone when
   the receiver does not acknowledge.
2. Every command waits up to a second for its UBX-ACK-ACK or UBX-ACK-NAK, which
   the sheet says comes "at least within one second".  A NAK, an acknowledge of
   another message and silence are all `false`.
3. `gnss_fix_new` is for a loop that sees each fix once; `gnss_fix` answers the
   latest and marks it taken.  Both read at most 512 bytes from the line.  At
   9600 baud a UBX-NAV-PVT frame is 100 bytes and takes 100 ms, so read at least
   every 100 ms; the line's own buffer is the board's.
4. A fix that is `FixNone` still has a time when the receiver has one.  A
   position is 0 unless the kind carries one, so check `kind` (or
   `gnss_has_position`) before using it.
5. UBX-NAV-PVT's `fixType` alone does not make a fix: `gnssFixOK` has to be set
   and `invalidLlh` clear, or the driver reports no fix.
6. NMEA is the fallback: until the first UBX-NAV-PVT arrives a GGA and an RMC
   with the same time make a fix, and after it the NMEA is ignored.  The NMEA
   position has the digits the receiver prints.
7. The satellites in view are the satellites used, since UBX-NAV-SAT is not
   parsed.
8. The measurement period is at least 25 ms on the M9 and 50 ms in the driver for
   the M8, and at most 65535 ms; `gnss_set_rate_mhz` rounds the period up, so the
   rate is at or below the one asked, and answers 0 for a rate below 16 mHz.
   The M9's rate is written to the RAM layer: a receiver that loses its power
   loses it.
9. `device_id` answers the protocol version the receiver names in its UBX-MON-VER
   `PROTVER=` string: 32 and 1 for SPG 4.04.  A `device_probe(32)` tells the M9
   from the M8, whose protocol is 18.
10. A frame with a wrong checksum is dropped and counted.  Bytes between frames
    are skipped, and a payload longer than the 256 bytes the reader keeps is
    checksummed without being stored.

## What is not included

- UBX-NAV-SAT (the satellites in view), UBX-NAV-DOP and the other navigation
  messages: only UBX-NAV-PVT, the acknowledges and UBX-MON-VER are parsed.
  NOT IMPLEMENTED.
- The AssistNow data (UBX-MGA) and the almanac and ephemeris messages.
  NOT IMPLEMENTED.
- The SPI port, the NMEA sentences other than GGA and RMC, RTCM, and the M9's
  other configuration items (constellations, the dynamic model, power save).
  NOT IMPLEMENTED.
- A baud rate scan: the program names the receiver's rate.
- `Gnss` on the DDC, and an awaitable form on a device.
- The configuration of the M8N's UBX-CFG-GNSS.

## Reference drivers read

Each of these was read for its fixes, and none was ported.  The fix is named at
its site in `src/`.

| Driver | What was taken from it |
|---|---|
| Zephyr `drivers/gnss/u_blox/gnss_u_blox_m8.c` and `_common.c` | the NMEA messages the driver does not want are switched off by UBX-CFG-MSG at rate 0; the navigation rate is a measurement period with `navRate` 1 and at least 50 ms; a second of wait after a baud rate change |
| `ublox` crate 0.10.0 | the Fletcher checksum over the class, identifier, length and payload; the UART mode word, character length at bit 6, parity at bit 9, stop bits at bit 12 (8N1 is 0x8C0); the parser that searches its buffer for the sync pair, which skips the NMEA text |

Embassy and esp-hal hold no u-blox driver.  Zephyr's `gnss_u_blox_m10.c`, which
the lane's brief also named, was fetched and not read in full; nothing here
comes from it.

## Related packages

- [devices-nv](https://novo-lang.org/packages/devices-nv) names the traits this
  driver implements, the fix it answers, and the register helpers the DDC form
  uses.
- [embedded-hal-nv](https://novo-lang.org/packages/embedded-hal-nv) names the
  `UartRx`, `UartTx`, `UartRxAsync` and `I2cBus` traits and the board handles.

## Tests

`novo test` runs the modules over doubles: a port that plays back one response
for each frame the driver sends and records the bytes it sends, an I2C bus with
the receiver's three registers, and a source of bytes to await.  It checks the
frame builders against the documents' bytes (the acknowledge, the poll, the
configuration messages), the reader against stray bytes, NMEA text, bad checksums
and long frames, a UBX-NAV-PVT frame derived by hand field by field and its fix,
the fix kinds, the time borrow, the NMEA reader on GGA and RMC sentences with
their checksums, every command with its acknowledge, its refusal and its silence,
and the three transports.  The derivation of the frame is in the suite's header.
`bash tests/coverage.sh` merges the suites' line coverage over `src/`.

**Hardware: NOT VERIFIED.**  See the top of this page.

## Licence

Apache-2.0.
