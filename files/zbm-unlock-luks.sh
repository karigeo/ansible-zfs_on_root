#!/bin/bash
# unlock-luks: remote LUKS unlock in ZFSBootMenu over dropbear (ansible-zfs_on_root).
#
# The zbm-luks-unlock early-setup hook asks for the passphrase on the console
# only and ZFSBootMenu waits until it is answered. This runs the same hook in
# the SSH session (same prompt, same keyfiles for the initramfs inject hook)
# and then ends the hook waiting on the console, so ZFSBootMenu continues.

hook=/libexec/hooks/early-setup.d/luks-unlock.sh
uuid_conf=/etc/zfsbootmenu/dracut.conf.d/zfsbootmenu-luks-uuids.conf

waiting=$(pgrep -f "$hook")
if [ -z "$waiting" ]; then
  echo "No LUKS passphrase prompt is waiting. Enter \"zbm\" to start ZFSBootMenu."
  exit 0
fi

"$hook"

# Same selection as the hook: the UUIDs from its config, otherwise all LUKS partitions.
# All of them must be open before the console prompt is ended, otherwise
# ZFSBootMenu would continue without the pool.
mapfile -t uuids < <(grep -vE '^\s*#' "$uuid_conf" 2>/dev/null | awk 'NF')
if [ ${#uuids[@]} -eq 0 ]; then
  mapfile -t uuids < <(lsblk -lnf -o UUID,FSTYPE | awk '$2 == "crypto_LUKS" {print $1}')
fi
missing=0
for uuid in "${uuids[@]}"; do
  if ! cryptsetup status "luks-${uuid}" >/dev/null 2>&1; then
    echo "Not unlocked: UUID ${uuid}"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "Run unlock-luks again."
  exit 1
fi

# shellcheck disable=SC2086
kill $waiting
echo "Unlocked. ZFSBootMenu continues on the console and boots the default"
echo "boot environment. Enter \"zbm\" to choose another one."
