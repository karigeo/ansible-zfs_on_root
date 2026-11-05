# Replacing a Disk

[Back to README.md](../README.md)

On multi-disk systems every disk holds the same partitions (see [Partition Layout](root-partition-settings.md#partition-layout)): a member of the ESP mirror `/dev/md/BOOT_EFI` (partition 1), of the swap array `/dev/md/swap` (2), of the root pool (3) and of the LVM array `/dev/md/lvm` (4). Swap and LVM only exist if they are enabled.

This is a checklist, not a tested procedure. Check every command against your system (`lsblk`, `cat /proc/mdstat`, `zpool status`, `/etc/crypttab`) before running it. `<old_disk>`, `<new_disk>` and `<existing_disk>` stand for `/dev/disk/by-id/...` names, the examples use the default pool name `rpool` (`root_pool_name`).

## Before Removing the Old Disk

Mark its partitions as failed and remove them from the `mdadm` arrays, so the arrays keep working in degraded state:

```shell
mdadm /dev/md/BOOT_EFI --fail <old_disk>-part1 --remove <old_disk>-part1
mdadm /dev/md/swap     --fail <old_disk>-part2 --remove <old_disk>-part2
mdadm /dev/md/lvm      --fail <old_disk>-part4 --remove <old_disk>-part4
```

## After Installing the New Disk

1. Copy the partition table from a remaining disk and give the copy new GUIDs:

    ```shell
    sgdisk --replicate=<new_disk> <existing_disk>
    sgdisk --randomize-guids <new_disk>
    ```

2. Add the new partitions to the `mdadm` arrays. The ARRAY lines in `/etc/mdadm/mdadm.conf` identify the arrays by UUID, so they stay valid.

    ```shell
    mdadm /dev/md/BOOT_EFI --add <new_disk>-part1
    mdadm /dev/md/swap     --add <new_disk>-part2
    mdadm /dev/md/lvm      --add <new_disk>-part4
    ```

3. LUKS only (`disk_encryption_type: luks`): create the container on the root partition with the same passphrase, add the keyfile used by the initramfs and open it with the name the role uses (`crypt_<new disk by-id name>_root`):

    ```shell
    cryptsetup luksFormat <new_disk>-part3
    cryptsetup luksAddKey <new_disk>-part3 /etc/cryptsetup-keys.d/rpool.key
    cryptsetup open <new_disk>-part3 crypt_<new disk by-id name>_root
    ```

    * `/etc/crypttab`: replace the line of the old container by one for the new container (`UUID=` from `blkid -s UUID -o value <new_disk>-part3`, same options).
    * `/etc/zfsbootmenu/dracut.conf.d/zfsbootmenu-luks-uuids.conf`: replace the UUID of the old root partition by the new one, so ZFSBootMenu unlocks the new container.

4. Replace the device in the root pool. The new device is the LUKS mapper (`/dev/mapper/crypt_..._root`) with LUKS, otherwise `<new_disk>-part3`:

    ```shell
    zpool status rpool          # name or GUID of the missing device
    zpool replace rpool <old device> <new device>
    ```

5. Make the new disk bootable:
    * UEFI: add a boot entry for its ESP and remove the entry of the old disk (`efibootmgr -b <num> -B`):

      ```shell
      efibootmgr --create --disk <new_disk> --part 1 --loader '\EFI\refind\refind_x64.efi' --label 'rEFInd <new disk by-id name>'
      ```

    * Legacy BIOS: write the syslinux boot code to the new disk:

      ```shell
      dd bs=440 count=1 conv=notrunc if=/usr/lib/syslinux/mbr/gptmbr.bin of=<new_disk>
      ```

6. Rebuild the initramfs and the ZFSBootMenu image (picks up crypttab and the LUKS UUID list):

    ```shell
    update-initramfs -u -k all
    generate-zbm --debug
    ```

Wait until `cat /proc/mdstat` and `zpool status` show the resync and resilver as finished.

[Back to README.md](../README.md)
