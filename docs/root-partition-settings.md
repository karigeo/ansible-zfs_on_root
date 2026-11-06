# Root Partition Settings

[Back to README.md](../README.md)

## Partition Layout

Every disk gets the same layout:

| Partition | Content | Type |
|-----------|---------|------|
| 1 | EFI system partition (512 MiB, FAT32, `boot_partition_size_mb` in `vars/main.yml`), mdadm mirror (metadata 1.0) on multiple disks | EF00, legacy BIOS bootable attribute (syslinux) |
| 2 | Swap (optional, `enable_swap_partitions`) | 8200, FD00 (mdadm) on multiple disks |
| 3 | ZFS root pool | BF00, 8309 (LUKS) |
| 4 | LVM (optional, `create_lvm_partition`) | 8e00, 8309 (LUKS), FD00 (mdadm) on 3+ disks |

The partition numbers are fixed: without swap there is no partition 2, the others keep their numbers.

With multiple disks the firmware sees each ESP member as a plain FAT32 partition. Anything that writes to the ESP outside Linux (firmware, rEFInd) changes only that member and the mirror diverges silently. The role therefore sets `use_nvram true` in `refind.conf` (rEFInd keeps its variables in NVRAM); don't take rEFInd screenshots (F10) or install tools from the firmware side onto the ESP.

## Define the ZFS Pool Name

```yaml
# Name of the root pool
root_pool_name: "rpool"

# Name of the dataset for the root filesystem
# {{ root_pool_name }}/ROOT/{{ root_dataset_name }}
root_dataset_name: "pve-1"
```

Based on the names above:

* The operating system is within ZFS dataset `rpool/ROOT/pve-1` (the boot environment).
* User data is stored in ZFS dataset `rpool/ROOT/home` (and `rpool/ROOT/home/root` for `/root`), outside of the OS dataset.
* For Proxmox VE, `rpool/ROOT/pve-1/var/lib/vz`, `rpool/ROOT/pve-1/etc-pve` and `rpool/data` are created as well.

NOTE: The operating system dataset (`rpool/ROOT/pve-1`, without its child datasets such as `var/log`) gets a snapshot `@apt_<date>` before every `apt`/`dpkg` run, and `@base_install` at the end of the installation. This allows the OS to be rolled back to previous snapshots without impacting user data.

## Root Partition Size

`root_partition_size` is the size of the root partition on each device:

```yaml
# Examples:
# "+256G" will create partition 256Gib in size
# "-200M" will use all available space, minus 200Mib
# "0" (zero) use all available space
root_partition_size: "-200G"
```

* `0` uses all remaining space of each device. Only use it without LVM partition (`create_lvm_partition: false`), otherwise there is no space left for it.
* A positive size (`+256G`) gives standard size partitions on each computer.
* A negative size (`-200G`) uses all space except the given amount, which is left for the LVM partition (or stays unallocated without LVM).
* If devices of different size are used, the root pool is limited by the smallest device. Space not used by the partitions stays unallocated at the end of the disk; when the smallest device is replaced later, partitions can be adjusted and the pool expanded.

## LVM Partition

An optional LVM partition (e.g. as Proxmox VE `lvmthin` storage) can be created after the root partition:

```yaml
create_lvm_partition: true

# LVM partition size when one or two devices are used
single_or_mirror_lvm_partition_size: "0"

# LVM partition size, per device, when three or more devices are used.
# They form an mdadm raid5, usable size is: (#devices - 1) * size
raidz_lvm_partition_size: "0"

# Volume group and (thin) logical volume created on the LVM partition
lvm_vg_name: pve
lvm_volume_name: data
lvm_volume_is_thin: true
lvm_volume_size: "99%VG"
```

* With 2 devices the LVM partitions form an mdadm mirror, with 3 or more devices an mdadm raid5.
* With encryption (`luks` or `native`) the volume group lives in a LUKS container, unlocked at boot with a keyfile stored on the encrypted root.
* The LVM partition is created after the root partition: `0` uses the rest of the disk, so `root_partition_size` must leave room for it (e.g. `-200G`). With a fixed LVM size (e.g. `+100G`) use a fixed root size or a negative one that leaves at least that much (e.g. `-200G`); `root_partition_size: "0"` is refused by the sanity checks then.

---

## ZFS Specific Adjustable Settings

Define ZFS Root Pool Type Rules:

* An even number of 4 or more devices of type `mirror` becomes [mirrored vdev pairs](root-pools-multi-mirrored-vdevs.md).
  * This is the recommended way to configure ZFS with many devices instead of using `raidz`.
  * This gives higher performance and much faster recovery from a single disk failure.
  * If you don't want this, use `raidz` or `raidz2`.
* 3 devices can be a `raidz` or a 3-way `mirror`. 5, 7, ... devices must be `raidz` or `raidz2` (an odd number of 5 or more devices of type `mirror` is refused).
  * A `raidz2` requires 4 or more devices.
* 1 device must be `""` (single device), 2 devices must be `mirror`.
* You can add additional entries to meet your requirements. Anything not defined will be treated as `raidz` pool (`default`).

  ```yaml
  set_root_pool_type:
    1: ""         # single device
    2: "mirror"
    3: "raidz"
    4: "mirror"
    5: "raidz"
    6: "mirror"
    default: "raidz"
  ```

## Ashift Value

The ZFS `ashift` value for modern devices with 512 byte or 4K sector size should be `12`. Some flash devices could see better performance with `13` as internally they might be 8K devices. Many devices simply lie about what they truly are due to compatibility reasons.

```yml
# Define ZFS ashift value to use
zfs_rpool_ashift: 12
```

* If `ashift` is too high, you lose a bit of space if you have a massive amount of very small files. If it's too low, you get write amplification and performance degradation.

## Encryption

See [Disk Encryption Settings](zfs-encryption-settings.md).

[Back to README.md](../README.md)
