#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/reference"
UBUNTU_DIR="$ROOT/inputs/ubuntu"
BASE_XZ="$UBUNTU_DIR/ubuntu-26.04.1-preinstalled-server-arm64.img.xz"
BASE_IMG="$ROOT/work/ubuntu-base.img"
OUT="$ROOT/output"
TMP="$ROOT/work/image-build"

KVER="6.12.61"
DTB="rk3568-inmys-smarc-evm.dtb"
P1_START=32768
P1_SECTORS=$((8 * 1024 * 1024 * 1024 / 512))
P2_START=$((P1_START + P1_SECTORS))
P2_SECTORS=$((2 * 1024 * 1024 * 1024 / 512))
TOTAL_SECTORS=$((P2_START + P2_SECTORS))
TOTAL_BYTES=$((TOTAL_SECTORS * 512))

BASE_LOOP=""
ACTIVE_LOOP=""
BASE_MNT="$TMP/base"
ROOT_MNT="$TMP/root"

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
cleanup() {
    set +e
    mountpoint -q "$ROOT_MNT" && umount "$ROOT_MNT"
    [[ -n "$ACTIVE_LOOP" ]] && losetup -d "$ACTIVE_LOOP"
    mountpoint -q "$BASE_MNT" && umount "$BASE_MNT"
    [[ -n "$BASE_LOOP" ]] && losetup -d "$BASE_LOOP"
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || fail "Run with sudo: sudo $0"
for tool in xz sha256sum losetup lsblk mount umount mountpoint rsync mkfs.ext4 sfdisk dd openssl truncate; do need "$tool"; done

[[ -f "$BASE_XZ" ]] || fail "Ubuntu image missing. Run ./scripts/download_ubuntu.sh first"
[[ -f "$UBUNTU_DIR/SHA256SUMS" ]] || fail "Official SHA256SUMS missing. Run ./scripts/download_ubuntu.sh first"
[[ -d "$REF/modules/$KVER" ]] || fail "Reference kernel modules missing; install the reference bundle"
[[ -f "$REF/kernel/Image" ]] || fail "Missing reference kernel Image"
[[ -f "$REF/kernel/$DTB" ]] || fail "Missing reference DTB"
[[ -f "$REF/boot/u-boot-rockchip.bin" ]] || fail "Missing reference U-Boot"
[[ -f "$REF/rockchip/rk3568_ddr_1332MHz_v1.23.bin" ]] || fail "Missing DDR loader"
[[ -f "$REF/rockchip/rk356x_usbplug_v1.17.bin" ]] || fail "Missing USB loader"

EXPECTED_SHA256="$(awk -v file="$(basename "$BASE_XZ")" '$2 == "*" file || $2 == file { print $1 }' "$UBUNTU_DIR/SHA256SUMS")"
[[ "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "Ubuntu image entry not found in SHA256SUMS"
printf '%s  %s\n' "$EXPECTED_SHA256" "$BASE_XZ" | sha256sum --check

mkdir -p "$OUT" "$TMP" "$BASE_MNT" "$ROOT_MNT"
rm -f "$OUT/ubuntu-emmc.img" "$OUT/ubuntu-sd.img"

if [[ ! -s "$BASE_IMG" || "$BASE_XZ" -nt "$BASE_IMG" ]]; then
    echo "[1/6] Decompressing Ubuntu base image..."
    xz -t "$BASE_XZ"
    xz -T0 -dc "$BASE_XZ" > "$BASE_IMG.part"
    mv "$BASE_IMG.part" "$BASE_IMG"
else
    echo "[1/6] Using cached decompressed Ubuntu base image."
fi

echo "[2/6] Mounting Ubuntu root filesystem..."
BASE_LOOP="$(losetup --find --show --partscan "$BASE_IMG")"
udevadm settle || true
BASE_PART=""
while read -r name fstype; do
    if [[ "$fstype" == "ext4" ]]; then BASE_PART="$name"; break; fi
done < <(lsblk -nrpo NAME,FSTYPE "$BASE_LOOP")
[[ -n "$BASE_PART" ]] || fail "No ext4 partition found in the Ubuntu base image"
mount -o ro,noload "$BASE_PART" "$BASE_MNT"

read -rsp "Password for Ubuntu user 'user': " PW1; echo
read -rsp "Repeat password: " PW2; echo
[[ -n "$PW1" ]] || fail "Empty password"
[[ "$PW1" == "$PW2" ]] || fail "Passwords do not match"
PASS_HASH="$(printf '%s' "$PW1" | openssl passwd -6 -stdin)"
unset PW1 PW2

create_variant() {
    local disk_id="$1"
    local store_label="$2"
    local image="$3"
    local root_img="$TMP/rootfs-$disk_id.ext4"
    local store_img="$TMP/store-$disk_id.ext4"
    local root_partuuid="${disk_id}-01"

    echo "[3/6] Creating Ubuntu rootfs for $image..."
    truncate -s 8G "$root_img"
    mkfs.ext4 -q -F -m 0 -L rootfs "$root_img"
    ACTIVE_LOOP="$(losetup --find --show "$root_img")"
    mount "$ACTIVE_LOOP" "$ROOT_MNT"
    rsync -aHAXx --numeric-ids "$BASE_MNT/" "$ROOT_MNT/"

    # Install the kernel/DTB and matching modules built for this RK3568 board.
    mkdir -p "$ROOT_MNT/boot"
    find "$ROOT_MNT/boot" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    install -D -m 0644 "$REF/kernel/Image" "$ROOT_MNT/boot/Image"
    install -D -m 0644 "$REF/kernel/$DTB" "$ROOT_MNT/boot/$DTB"
    mkdir -p "$ROOT_MNT/boot/extlinux"
    cat > "$ROOT_MNT/boot/extlinux/extlinux.conf" <<CONF
TIMEOUT 3
DEFAULT ubuntu

LABEL ubuntu
    KERNEL /boot/Image
    FDT /boot/$DTB
    APPEND earlycon=uart8250,mmio32,0xfe660000 console=ttyS2,1500000 root=PARTUUID=$root_partuuid rootwait rw ds=nocloud;s=/var/lib/cloud/seed/nocloud/
CONF

    mkdir -p "$ROOT_MNT/lib/modules/$KVER"
    rsync -aHAX "$REF/modules/$KVER/" "$ROOT_MNT/lib/modules/$KVER/"
    if [[ -d "$REF/firmware" ]]; then
        mkdir -p "$ROOT_MNT/lib/firmware"
        rsync -a "$REF/firmware/" "$ROOT_MNT/lib/firmware/"
    fi

    cat > "$ROOT_MNT/etc/fstab" <<FSTAB
PARTUUID=$root_partuuid / ext4 defaults,noatime 0 1
LABEL=$store_label /opt ext4 defaults,noatime 0 2
FSTAB
    mkdir -p "$ROOT_MNT/opt"
    echo "nms-sm-rk3568" > "$ROOT_MNT/etc/hostname"
    cat > "$ROOT_MNT/etc/hosts" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 nms-sm-rk3568
::1 localhost ip6-localhost ip6-loopback
HOSTS

    mkdir -p "$ROOT_MNT/etc/netplan"
    find "$ROOT_MNT/etc/netplan" -type f -name '*.yaml' -delete
    cat > "$ROOT_MNT/etc/netplan/99-rk3568.yaml" <<'NETPLAN'
network:
  version: 2
  renderer: networkd
  ethernets:
    wired:
      match:
        name: "e*"
      dhcp4: true
NETPLAN

    rm -rf "$ROOT_MNT/var/lib/cloud"
    mkdir -p "$ROOT_MNT/var/lib/cloud/seed/nocloud" "$ROOT_MNT/etc/cloud/cloud.cfg.d"
    cat > "$ROOT_MNT/etc/cloud/cloud.cfg.d/99-rk3568.cfg" <<'CLOUDCFG'
datasource_list: [ NoCloud ]
CLOUDCFG
    cat > "$ROOT_MNT/var/lib/cloud/seed/nocloud/meta-data" <<META
instance-id: rk3568-ubuntu-$disk_id
local-hostname: nms-sm-rk3568
META
    cat > "$ROOT_MNT/var/lib/cloud/seed/nocloud/user-data" <<USERDATA
#cloud-config
hostname: nms-sm-rk3568
manage_etc_hosts: true
ssh_pwauth: true
users:
  - default
  - name: user
    gecos: RK3568 User
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: '$PASS_HASH'
USERDATA
    : > "$ROOT_MNT/etc/machine-id"

    for unit in systemd-networkd.service ssh.service; do
        if [[ -f "$ROOT_MNT/usr/lib/systemd/system/$unit" || -f "$ROOT_MNT/lib/systemd/system/$unit" ]]; then
            systemctl --root="$ROOT_MNT" enable "$unit" >/dev/null 2>&1 || true
        fi
    done

    umount "$ROOT_MNT"
    losetup -d "$ACTIVE_LOOP"
    ACTIVE_LOOP=""

    echo "[4/6] Creating disk image $image..."
    truncate -s "$TOTAL_BYTES" "$image"
    sfdisk "$image" <<PARTITIONS
label: dos
label-id: 0x$disk_id
unit: sectors

start=$P1_START, size=$P1_SECTORS, type=83
start=$P2_START, size=$P2_SECTORS, type=83
PARTITIONS

    dd if="$REF/boot/u-boot-rockchip.bin" of="$image" bs=512 seek=64 conv=notrunc status=none
    dd if="$root_img" of="$image" bs=4M seek=4 conv=notrunc,sparse status=progress

    truncate -s 2G "$store_img"
    mkfs.ext4 -q -F -m 0 -L "$store_label" "$store_img"
    dd if="$store_img" of="$image" bs=4M seek=2052 conv=notrunc,sparse status=none

    rm -f "$root_img" "$store_img"
    echo "Created: $image"
}

create_variant "35680001" "STORE" "$OUT/ubuntu-emmc.img"
create_variant "35680002" "STORE_SD" "$OUT/ubuntu-sd.img"

echo "[6/6] Finished."
ls -lh "$OUT/ubuntu-emmc.img" "$OUT/ubuntu-sd.img"
