# Emergency chroot Recovery from Live CD

[Back to README.md](../README.md)

## Emergency chroot Recovery

This will mount all pools and file systems under the `/mnt` directory. The examples use the default names `rpool` (`root_pool_name`) and `pve-1` (`root_dataset_name`).

1. Boot the Debian Live CD:
    * Select option <button name="button">Live</button>.
    * Standard image: use the console (user `user`, password `live`). Desktop image: open a terminal.

2. Become Root

    ```shell
    sudo -i
    ```

3. Install ZFS and the tools needed for the chroot environment. ZFS is in `contrib`: add `contrib` to the components of the live CD's apt sources (`/etc/apt/sources.list` or `/etc/apt/sources.list.d/*.sources`) first. The headers must match the running live CD kernel, which is usually older than `linux-headers-amd64` in the archive.

    ```shell
    apt-get update
    apt-get install --yes linux-headers-$(uname -r) zfs-dkms zfsutils-linux mdadm cryptsetup
    modprobe zfs
    ```

4. LUKS only: open the LUKS containers of the root partitions (partition `3` of every disk)

    ```shell
    cryptsetup open /dev/disk/by-id/<disk>-part3 crypt_<disk>_root
    ```

    * Repeat for every disk (`<disk>` is the by-id name). The mapper names do not matter for ZFS, it finds the pool on any of them.

5. Export all pools (in case anything was automatically imported)

    ```shell
    zpool export -a
    ```

6. Import the ZFS pool, load the encryption key (native encryption only) and mount to `/mnt`

    ```shell
    zpool import -f -N -R /mnt rpool
    # native encryption only: the keyfile is inside the pool, so prompt for the passphrase
    zfs load-key -L prompt rpool

    zfs mount rpool/ROOT/pve-1
    zfs mount -a
    ```

7. Mount the boot partition to `/mnt/boot/efi`

    ```shell
    # single disk
    mount /dev/disk/by-id/<disk>-part1 /mnt/boot/efi

    # multiple disks: assemble the mdadm mirror of all ESP partitions first
    # (never mount a single member, writes would make the mirror diverge)
    mdadm --assemble /dev/md/BOOT_EFI /dev/disk/by-id/<disk1>-part1 /dev/disk/by-id/<disk2>-part1
    mount /dev/md/BOOT_EFI /mnt/boot/efi
    ```

8. Mount Live CD paths to build the chroot environment

    ```shell
    mount -t proc /proc /mnt/proc
    mount -t sysfs sys /mnt/sys
    mount -B /dev /mnt/dev
    mount -t devpts pts /mnt/dev/pts
    ```

9. Enter the chroot environment

    ```shell
    chroot /mnt bash
    ```

    * You are now within the chroot environment and can issue commands as if you have booted from it. You can troubleshoot, view logs, apply patches, work on ZFS items, whatever is needed to get your system bootable again.

    * If you need to regenerate the initramfs of the system and the ZFSBootMenu image:

      ```shell
      update-initramfs -u -k all
      generate-zbm --debug
      ```

10. Exit chroot when ready (return to Live CD environment)

    ```shell
    exit
    ```

11. Unmount everything and export all ZFS pools

    ```shell
    umount /mnt/boot/efi
    umount -n /mnt/{dev/pts,dev,sys,proc}

    zfs unmount -a
    zpool export -a
    ```

It is now safe to exit the Debian Live CD and reboot the system. If you could not fix your issue, repeat the steps above.

[Back to README.md](../README.md)
