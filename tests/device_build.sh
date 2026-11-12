#!/usr/bin/env bash
# tests/device_build.sh — builds the device program,
# examples/position_log.nv, for two boards and reports the image sizes.
#
# The program is a firmware `main`, so it is built as the `main` of a
# scratch package that depends on this one by path, the way a program on
# a device depends on it.  The boards are the Nordic nRF52840-DK and
# nRF54LM20-DK.  Each is built for the log transport (RTT) and with
# --hci-uart=physical, which makes the board's UART the line the receiver is
# read on.  Nothing is flashed.  The emulated board's image (nrf52-qemu) is
# then run under QEMU, where no receiver sends a byte, and its first line must
# be the program's refusal.
#
# Run from anywhere:  bash tests/device_build.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
NOVO="${NOVO:-$HOME/.novo/bin/novo}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-m9n-nv-dev.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/src"
cp "$PKG/examples/position_log.nv" "$WORK/src/main.nv"
cat > "$WORK/novo.toml" <<EOF
[package]
name    = "neo-m9n-nv-device"
version = "0.1.0"
main    = "src/main.nv"

[dependencies]
neo-m9n-nv     = { path = "$PKG" }
devices-nv      = { path = "$PKG/../devices-nv" }
embedded-hal-nv = { path = "$PKG/../embedded-hal-nv" }
EOF

fail=0
for target in nrf52840-dk nrf54lm20-dk nrf52840-dk+uart nrf54lm20-dk+uart nrf52-qemu; do
  rm -f "$WORK/main.elf"
  flags=""
  board="${target%+uart}"
  if [ "$board" != "$target" ]; then flags="--hci-uart=physical"; fi
  ( cd "$WORK" && NOVO_LEAK_CHECK=0 timeout 900 "$NOVO" build --target="$board" $flags src/main.nv ) \
    > "$WORK/$target.log" 2>&1
  if [ -f "$WORK/main.elf" ]; then
    flash=$(grep -m1 '^  flash ' "$WORK/$target.log" | sed 's/^  flash *//')
    ram=$(grep -m1 '^  .data + .bss' "$WORK/$target.log" | sed 's/^  .data + .bss *//')
    echo "  ✓ examples/position_log.nv builds for --target=$target: flash $flash"
    echo "      .data + .bss $ram"
    cp "$WORK/main.elf" "$WORK/$target.elf"
  else
    echo "  ✗ examples/position_log.nv does not build for --target=$target"
    grep -vE '^novo:' "$WORK/$target.log" | head -20 | sed 's/^/      /'
    fail=1
  fi
done

# The emulated board: an MPS2 AN386 Cortex-M4, whose UART output reaches
# the host through semihosting.  With no receiver the
# program prints its refusal and returns.
if ! command -v qemu-system-arm >/dev/null 2>&1; then
  echo "  - the image is not run: qemu-system-arm is not installed"
elif [ -f "$WORK/nrf52-qemu.elf" ]; then
  out=$(timeout 8 qemu-system-arm -machine mps2-an386 -nographic -semihosting \
          -kernel "$WORK/nrf52-qemu.elf" 2>&1 | tr -d '\000' | head -20)
  if printf '%s\n' "$out" | tr -d '\r' | grep -aq 'neo: no answer'; then
    echo "  ✓ the image runs under QEMU and reports that the part does not answer"
  else
    echo "  ✗ the image under QEMU did not report that the part does not answer"
    printf '%s\n' "$out" | head -10 | sed 's/^/      /'
    fail=1
  fi
fi
exit "$fail"
