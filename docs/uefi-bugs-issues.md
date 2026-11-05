# UEFI BIOS Bugs / Glitches / Issues

[Back to README.md](../README.md)

## Limited UEFI Lookup Table

On [Minisform U560](https://store.minisforum.com/products/um560) after the 1st reboot it went directly into AMI BIOS screen.  It acted as if there were no bootable devices within the system.  Pressing `F7` for boot menu found no devices.  This is NOT typical of a UEFI system.

* Some UEFI BIOS are hardcoded to look for specific files on the ESP partition (mounted at `/boot/efi`). Minisform U560 was looking for `EFI/boot/bootx64.efi` which is not used by rEFInd boot manager.
* The `sudo efibootmgr -v` from within the Debian Live CD can be used to view the current UEFI lookup table.
* rEFInd boot manager will generate a `EFI/refind/refind_x64.efi` image.

NOTE: On multi-disk UEFI installs the role already creates a UEFI boot entry `rEFInd <disk-id>` for the ESP of every disk (task `install_refind`).

I needed to add a reference to the `refind_x64.efi` image FOR EACH bootable device in the system - a SATA SSD (`sda`) and NVMe SSD (`nvme0n1`). Before the 1st reboot of the target system, while still within the Debian Live CD environment, I used the following:

```shell
efibootmgr --create --gpt --disk /dev/sda --part 1 -w --loader "\\EFI\\refind\\refind_x64.efi" --label "rEFInd-sda1"
efibootmgr --create --gpt --disk /dev/nvme0n1 --part 1 -w --loader "\\EFI\\refind\\refind_x64.efi" --label "rEFInd-nvme0n1p1"
```

* This created two UEFI table entries for the `refind_x64.efi` for both the SATA SSD (`sda`) and NVMe SSD (`nvme0n1`) partition `1`.  The double slashes `\\` are required. One is called `rEFInd-sda1` and the other is `rEFInd-nvme0n1p1`.
* The system was bootable once this modification was made.

NOTE: This is specific to the existing partition disk partitions.  Each time I deleted partitions and created them again I had to delete these references and recreate them.

```shell
$ sudo efibootmgr -v

BootCurrent: 0001
Timeout: 2 seconds
BootOrder: 0001,0000
Boot0000* rEFInd-sda1   HD(1,GPT,0f9f662c-b836-45f6-8382-4c5f697cf02c,0x800,0x100000)/File(\EFI\refind\refind_x64.efi)
Boot0001* rEFInd-nvme0n1p1      HD(1,GPT,8144c406-567a-4bcb-b409-3e1389bbe7ec,0x800,0x100000)/File(\EFI\refind\refind_x64.efi)
```

[Back to README.md](../README.md)
