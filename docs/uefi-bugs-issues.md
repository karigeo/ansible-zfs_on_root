# UEFI BIOS Bugs / Glitches / Issues

[Back to README.md](../README.md)

## No Bootable Device after the First Reboot

Some UEFI firmware does not boot the new system after the first reboot and goes straight to its setup screen, as if there were no bootable device. This was seen on a [Minisforum UM560](https://store.minisforum.com/products/um560): its boot menu (`F7`) found no devices.

rEFInd is installed as `EFI/refind/refind_x64.efi` on the ESP, not as the fallback loader `EFI/BOOT/BOOTX64.EFI` that some firmware looks for. The firmware needs a UEFI boot entry pointing to rEFInd:

* Single disk, UEFI mode: `refind-install` creates the entry.
* Multiple disks, UEFI mode: the role creates one entry `rEFInd <disk-id>` for the ESP of every disk (task `install_refind`).
* Installed in legacy BIOS mode: no entry exists.

Check the entries with `sudo efibootmgr -v` (from the live CD or the installed system). If an entry is missing or the firmware dropped it, create one per disk with the same loader path the role uses:

```shell
efibootmgr --create --disk /dev/disk/by-id/<disk> --part 1 --loader '\EFI\refind\refind_x64.efi' --label 'rEFInd <disk>'
```

Example output with two disks:

```shell
$ sudo efibootmgr -v

BootCurrent: 0001
Timeout: 2 seconds
BootOrder: 0001,0000
Boot0000* rEFInd ata-<disk1>   HD(1,GPT,0f9f662c-b836-45f6-8382-4c5f697cf02c,0x800,0x100000)/File(\EFI\refind\refind_x64.efi)
Boot0001* rEFInd nvme-<disk2>  HD(1,GPT,8144c406-567a-4bcb-b409-3e1389bbe7ec,0x800,0x100000)/File(\EFI\refind\refind_x64.efi)
```

The entries point to the partition GUID of the ESP. After repartitioning a disk (e.g. a reinstall), delete the old entries (`efibootmgr -b <num> -B`) and create new ones.

[Back to README.md](../README.md)
