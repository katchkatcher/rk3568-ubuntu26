#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/reference"
DIST="$ROOT/dist"
BUNDLE_VERSION="${REFERENCE_BUNDLE_VERSION:-v1}"
ARCHIVE="$DIST/rk3568-ubuntu-reference-assets-$BUNDLE_VERSION.tar.gz"

[[ -d "$REF/modules/6.12.61" ]] || { echo "ERROR: reference assets missing; run import_reference_assets.sh first" >&2; exit 1; }
[[ -f "$REF/SHA256SUMS" ]] || { echo "ERROR: reference/SHA256SUMS not found" >&2; exit 1; }
(
    cd "$REF"
    sha256sum --check SHA256SUMS
)
mkdir -p "$DIST"
tar -czf "$ARCHIVE" -C "$ROOT" reference
(cd "$DIST" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
echo "Created: $ARCHIVE"
echo "Archive checksum: $ARCHIVE.sha256"
