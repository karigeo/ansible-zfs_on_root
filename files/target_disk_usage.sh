#!/bin/bash
# Print "<disk> <mount point>" for every target disk that backs a mounted
# filesystem outside the install mount point, e.g. the running system's root
# or the live medium. ZFS mounts are resolved via their pool's vdevs, block
# devices via lsblk (through partitions, md, LUKS and LVM). A ZFS mount whose
# vdevs cannot be resolved is reported with "?" as disk.
# Usage: target_disk_usage.sh <install mount point> <disk>...
set -u

mnt=$1
shift
declare -A target
for disk in "$@"; do
  target[$(readlink -f "$disk")]=1
done

# findmnt -r escapes spaces etc. in mount points as \xHH
findmnt -rn -o TARGET,FSTYPE,SOURCE | while read -r mountpoint fstype source; do
  mountpoint=$(printf '%b' "$mountpoint")
  case "$mountpoint" in "$mnt" | "$mnt"/*) continue ;; esac

  if [ "$fstype" = zfs ]; then
    devices=$(zpool list -v -H -P "${source%%/*}" 2>/dev/null | awk '$1 ~ "^/dev/" {print $1}')
    if [ -z "$devices" ]; then
      echo "? $mountpoint"
      continue
    fi
  else
    # btrfs subvolume mounts show as /dev/sdX[/subvol]
    devices=${source%%\[*}
  fi

  for device in $devices; do
    [ -b "$device" ] || continue
    lsblk -s -n -r -p -o NAME,TYPE "$device" | while read -r name type; do
      if [ "$type" = disk ] && [ -n "${target[$(readlink -f "$name")]:-}" ]; then
        echo "$name $mountpoint"
      fi
    done
  done
done | sort -u
