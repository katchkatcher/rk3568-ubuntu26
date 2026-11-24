#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:?Usage: $0 /path/to/rk3568-ubuntu-reference-assets-v1.tar.gz}"
STAGE="$ROOT/work/reference-install"

[[ -f "$ARCHIVE" ]] || { echo "ERROR: archive not found: $ARCHIVE" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "ERROR: tar is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "ERROR: sha256sum is required" >&2; exit 1; }
if [[ -f "$ARCHIVE.sha256" ]]; then
    (cd "$(dirname "$ARCHIVE")" && sha256sum --check "$(basename "$ARCHIVE").sha256")
fi
mkdir -p "$ROOT/work"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# Only allow paths below the expected top-level reference/ directory.
while IFS= read -r entry; do
    case "$entry" in
        reference|reference/*) ;;
        *) echo "ERROR: unexpected path in archive: $entry" >&2; exit 1 ;;
    esac
done < <(tar -tzf "$ARCHIVE")

tar -xzf "$ARCHIVE" -C "$STAGE" --no-same-owner
[[ -f "$STAGE/reference/SHA256SUMS" ]] || { echo "ERROR: bundle has no SHA256SUMS" >&2; exit 1; }
(
    cd "$STAGE/reference"
    sha256sum --check SHA256SUMS
)
[[ -f "$STAGE/reference/kernel/Image" ]] || { echo "ERROR: kernel Image missing" >&2; exit 1; }
[[ -f "$STAGE/reference/kernel/rk3568-inmys-smarc-evm.dtb" ]] || { echo "ERROR: DTB missing" >&2; exit 1; }
[[ -f "$STAGE/reference/boot/u-boot-rockchip.bin" ]] || { echo "ERROR: U-Boot missing" >&2; exit 1; }
[[ -d "$STAGE/reference/modules/6.12.61" ]] || { echo "ERROR: kernel modules missing" >&2; exit 1; }

rm -rf "$ROOT/reference"
mv "$STAGE/reference" "$ROOT/reference"
echo "Reference bundle installed and verified: $ROOT/reference"
