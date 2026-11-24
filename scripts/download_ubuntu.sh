#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/inputs/ubuntu"
BASE_URL="https://cdimage.ubuntu.com/ubuntu/releases/26.04.1/release"
FILE="ubuntu-26.04.1-preinstalled-server-arm64.img.xz"
EXPECTED_SHA256="189b1aec3eaf9544a51dba4e6ac3f4d5d24fd1031ed0263fa5ea78f1824934c1"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: требуется команда '$1'" >&2; exit 1; }; }
need curl
need sha256sum

mkdir -p "$DEST"
SUMS_TMP="$DEST/SHA256SUMS.tmp"
IMAGE_TMP="$DEST/$FILE.part"
trap 'rm -f "$SUMS_TMP" "$IMAGE_TMP"' EXIT

echo "[1/3] Получение официального SHA256SUMS..."
curl --fail --location --retry 3 --retry-delay 2 \
    "$BASE_URL/SHA256SUMS" -o "$SUMS_TMP"

PUBLISHED_SHA256="$(awk -v file="$FILE" '$2 == "*" file || $2 == file { print $1 }' "$SUMS_TMP")"
[[ "$PUBLISHED_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: в официальном SHA256SUMS не найдена запись для $FILE" >&2
    exit 1
}
[[ "$PUBLISHED_SHA256" == "$EXPECTED_SHA256" ]] || {
    echo "ERROR: SHA256 в официальном манифесте отличается от зафиксированного значения." >&2
    echo "Expected: $EXPECTED_SHA256" >&2
    echo "Published: $PUBLISHED_SHA256" >&2
    echo "Проверьте релиз и обновите версию/контрольную сумму намеренно." >&2
    exit 1
}

if [[ -f "$DEST/$FILE" ]]; then
    echo "[2/3] Проверка уже загруженного образа..."
    printf '%s  %s\n' "$EXPECTED_SHA256" "$DEST/$FILE" | sha256sum --check --status && {
        cp "$SUMS_TMP" "$DEST/SHA256SUMS"
        echo "Образ уже загружен и прошёл проверку SHA256."
        exit 0
    }
    echo "Существующий файл не прошёл проверку; загружаю заново." >&2
    rm -f "$DEST/$FILE"
else
    echo "[2/3] Загрузка $FILE..."
fi

curl --fail --location --retry 3 --retry-delay 2 \
    "$BASE_URL/$FILE" -o "$IMAGE_TMP"
printf '%s  %s\n' "$EXPECTED_SHA256" "$IMAGE_TMP" | sha256sum --check
mv "$IMAGE_TMP" "$DEST/$FILE"
cp "$SUMS_TMP" "$DEST/SHA256SUMS"

echo "[3/3] Готово: $DEST/$FILE"
