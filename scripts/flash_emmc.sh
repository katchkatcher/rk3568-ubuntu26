#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="$ROOT/output/ubuntu-emmc.img"
REF="$ROOT/reference/rockchip"
XROCK="$(command -v xrock || true)"

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "Image not found: $IMAGE. Run build_images.sh first." >&2; exit 1; }
[[ -f "$REF/rk3568_ddr_1332MHz_v1.23.bin" ]] || { echo "DDR loader missing; install reference bundle." >&2; exit 1; }
[[ -f "$REF/rk356x_usbplug_v1.17.bin" ]] || { echo "USB loader missing; install reference bundle." >&2; exit 1; }
[[ -n "$XROCK" && -x "$XROCK" ]] || { echo "xrock not found in PATH." >&2; exit 1; }

cat <<WARNING
WARNING: this operation overwrites the eMMC of the connected RK3568 board.
Check that the board is in Maskrom mode and the correct USB device is connected.
WARNING
read -r -p "Type FLASH to continue: " CONFIRM
[[ "$CONFIRM" == "FLASH" ]] || { echo "Cancelled."; exit 0; }

"$XROCK" maskrom \
    "$REF/rk3568_ddr_1332MHz_v1.23.bin" \
    "$REF/rk356x_usbplug_v1.17.bin" \
    --rc4-off

"$XROCK" flash write 0 "$IMAGE"
echo "Ubuntu image flashed to eMMC."
