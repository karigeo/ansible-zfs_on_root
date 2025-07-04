# Emergency chroot Recovery from Live CD

[Back to README.md](../README.md)

## Emergency chroot Recovery

This will mount all pools and file systems under `/mnt` directory.

1. Boot the Debian Live CD:
    * Select option <button name="button">Live</button>.
    * Open a terminal within the Live CD environment - press <kbd>Ctrl</kbd> <kbd>Alt</kbd>-<kbd>T</kbd>.

2. Become Root

    ```shell
    sudo -i
    ```

3. Install packages to support chroot environment

    ```shell
    apt-get install mdadm
    ```

4. Export all pools (incase anything was automatically imported)

    ```shell
    zpool export -a
    ```

5. Import ZFS pool(s), load encryption keys and mount to `/mnt` directory

    ```shell
    zpool import -f -N -R /mnt {root_pool_name}
    zfs load-key -a

    zfs mount {root_pool_name}/ROOT/ubuntu
    zfs mount {root_pool_name}/ROOT/home/root

    zfs mount -a
    ```

    * The `{root_pool_name}` is unique to your system.  By default, this Ansible process names the pool after the hostname.  This is the equivalent of `rpool` in previous ZFS on Root methods.

6. Create mdadm array of boot partitions and mount to `/mnt/boot/efi` directory

    ```shell
    mdadm --assemble /dev/md127  /dev/sda1 /dev/nvme0n1p1
    mount /dev/md127 /mnt/boot/efi
    ```

    * Above assumes just 2 devices.  Each device uses partition `1` on that device (standard partition for booting).
    * You need to adjust the number of devices and device names such as`/dev/sda1` (SATA SSD) and `/dev/nvme0n1p1` (NVMe SSD) to match the names of whatever your system uses.

7. Mount Live CD paths to Build chroot Environment

    ```shell
    mount -t proc /proc /mnt/proc
    mount -t sysfs sys /mnt/sys
    mount -B /dev /mnt/dev
    mount -t devpts pts /mnt/dev/pts
    ```

8. Enter the chroot environment

    ```shell
    chroot /mnt bash
    ```

    * You are now within the chroot environment and can issue commands as if you have booted from it.  You can troubleshoot, view, logs, apply patches, work on ZFS items, whatever is needed to get your system bootable again.

    * If you needed to regenerate your boot initramfs:

      ```shell
      dracut -v -f --regenerate-all
      generate-zbm
      ```

9. Exit chroot when ready (return to Live CD environment)

    ```shell
    exit
    ```

10. Unmount everything and export all ZFS pools

    ```shell
    umount /mnt/boot/efi
    umount -n /mnt/{dev/pts,dev,sys,proc}

    zfs unmount -a
    zpool export -a
    ```

It is now safe to exit Debian Live CD and reboot system, hopefully you fixed your issues and can boot. If not repeat the steps above and keep on Googling that problem. :)

[Back to README.md](../README.md)
