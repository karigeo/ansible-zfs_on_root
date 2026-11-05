#!/bin/bash
# Builds the test live ISO: Debian Live standard + automatic boot + a live-config
# hook that runs files/do_ssh.sh and installs the test SSH key (see README.md).
# Input/output in $ZFS_TEST_DIR/iso:
#   download/<debian-live ISO>   (SHA512 checked against Debian's SHA512SUMS)
#   orig/                        (boot/grub/grub.cfg, isolinux/{isolinux,live}.cfg extracted from it)
# Usage: build.sh <debian-live ISO file name> <output ISO name>
set -euo pipefail
. "$(dirname "$0")/../bin/common.sh"
SRC_ISO=$1; OUT=$2
ROLE=$(cd "$TESTS_VM/../.." && pwd)
W=$ZFS_TEST_DIR/iso
cd "$W"
# noeject: don't wait for "remove the live-medium, press ENTER" at shutdown (legacy BIOS)
PARAMS="live-config.hostname=$VM_HOSTNAME noeject zfstest.ip=$VM_IP/$VM_PREFIX zfstest.gw=$VM_GW"
PARAMS="$PARAMS zfstest.dns=$VM_DNS zfstest.domain=$VM_DOMAIN"
PARAMS="$PARAMS live-config.hooks=file:///run/live/medium/live/config-hooks/zfs-test"
export PARAMS

rm -rf overlay && mkdir -p overlay/boot/grub overlay/isolinux overlay/live/config-hooks overlay/zfs-test
# UEFI: GRUB, boot the first entry after 3 s, no quiet/splash
perl -0pe 's/\A/set timeout=3\n/; s/quiet splash findiso/$ENV{PARAMS} findiso/' orig/boot/grub/grub.cfg > overlay/boot/grub/grub.cfg
# Legacy BIOS: isolinux, timeout in 1/10 s
sed 's/^timeout 0$/timeout 30/' orig/isolinux/isolinux.cfg > overlay/isolinux/isolinux.cfg
perl -0pe 's/append boot=live components quiet splash/append boot=live components $ENV{PARAMS}/' orig/isolinux/live.cfg > overlay/isolinux/live.cfg
install -m 0755 "$TESTS_VM/iso/hook.sh" overlay/live/config-hooks/zfs-test
install -m 0755 "$TESTS_VM/iso/prep.sh" overlay/zfs-test/prep.sh
install -m 0755 "$ROLE/files/do_ssh.sh" overlay/zfs-test/do_ssh.sh
install -m 0644 "$TEST_KEY.pub" overlay/zfs-test/authorized_keys

grep -cF "$PARAMS" overlay/boot/grub/grub.cfg overlay/isolinux/live.cfg
rm -f "$OUT"
xorriso -indev "download/$SRC_ISO" -outdev "$OUT" \
  -map overlay/boot/grub/grub.cfg /boot/grub/grub.cfg \
  -map overlay/isolinux/isolinux.cfg /isolinux/isolinux.cfg \
  -map overlay/isolinux/live.cfg /isolinux/live.cfg \
  -map overlay/live/config-hooks /live/config-hooks \
  -map overlay/zfs-test /zfs-test \
  -boot_image any replay 2>&1 | tail -3
shasum -a 256 "$OUT"
