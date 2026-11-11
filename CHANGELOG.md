# Changelog

## 0.1.0

The first release: a driver for u-blox's NEO-M9N GNSS receiver, and the NEO-M8N
as the second part of the family.

- `Neo`, the type a program builds with the board's UART and the model,
  implementing devices-nv's `Gnss` and `Identifiable`, with its own methods for
  the line, the baud rate and the output protocols.
- `ubx`: the UBX frame with its Fletcher checksum, `UbxReader`, which finds
  frames in a stream and skips the text between them, the builders for
  UBX-CFG-VALSET and UBX-CFG-VALGET (M9) and UBX-CFG-MSG, UBX-CFG-RATE and
  UBX-CFG-PRT (M8) and for polls, UBX-NAV-PVT as `UbxPvt` and as devices-nv's
  `GnssFix`, the acknowledges, and UBX-MON-VER's protocol version.
- `nmea`: a reader for GGA and RMC with the NMEA checksum, as the fallback
  while no UBX-NAV-PVT has arrived.
- `neo`: `NeoCore`, the stream of bytes, `NeoPort`, the line, the commands with
  their acknowledge wait (`enable_pvt`, `set_period`, `set_rate_mhz`,
  `nmea_off`, `change_baud`, `identify`, `begin_with`), and the one shared
  stream the trait methods use.
- `neo_ddc`: the receiver on its DDC (I2C) port: the byte count, the stream in
  pieces of 32, and a frame sent as one write.
- `neo_async.NeoAsync`: an implementation of `GnssAsync` for a host scheduler.
- A device program, `examples/position_log.nv`, and `tests/device_build.sh`,
  which builds it for the nRF52840 DK and the nRF54LM20 DK with the RTT log and
  with `--hci-uart=physical`, and runs the emulated board's image under QEMU.
- The suite runs over doubles and covers every line of `src/` except two
  excused ones; `tests/coverage.sh` measures it.

### Known

- Hardware verification: NOT VERIFIED.  No board carries a NEO-M9N or a NEO-M8N.
- The documents read are the M9 SPG 4.04 interface description UBX-21022436 R02
  and the M8 receiver description UBX-13003221 R15.  The NEO-M9N's own interface
  description, UBX-19035940, could not be fetched.
- UBX-NAV-SAT, UBX-NAV-DOP, the AssistNow data, the SPI port, the NMEA
  sentences other than GGA and RMC, RTCM, the M9's other configuration items and
  UBX-CFG-GNSS are not implemented.  The satellites in view are the satellites
  used.
- A trait method gets a plain `self`, so the stream's state is one module-level
  `NeoCore`: one receiver per program for the trait methods.
- `NeoAsync` is a plain struct because an `async fn` cannot take a `@value`
  struct (E2015); an `async fn` is refused at the embedded tier, so it is for a
  host scheduler.  A device program polls.
- The M8's UBX-CFG-PRT mode word 0x8C0 is from the `ublox` crate; the bit
  positions are in the data sheet's bitfield graphic, which its text does not
  carry.
- Two regions are excused from the coverage gate with their reasons: the
  UART read of the board, which a host has no byte for, and the end of the NMEA
  field scan, which a checked sentence cannot reach.
- The images are 17,548 and 18,436 bytes of flash for the nRF52840 DK and the
  nRF54LM20 DK with the RTT log, and 18,764 and 19,924 with
  `--hci-uart=physical`.  A fix from a receiver over either UART is NOT VERIFIED.
