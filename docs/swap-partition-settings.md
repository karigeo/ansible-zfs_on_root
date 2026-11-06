# Swap Partition Settings

[Back to README.md](../README.md)

* For a `single device`, swap uses the device's swap partition (`-part2`) directly.
* For `two devices` the swap partitions are joined into an `mdadm` based `mirror` (`/dev/md/swap`) across both devices. The size stays the same (if you define 4096 MB then it will be that size).
* For `three or more devices` the swap partitions are joined into an `mdadm` based `RAID10` across the disk devices.
  * The usable swap size is `(number of devices x raidz_swap_partition_size_mb) / 2`.
* With encryption (`disk_encryption_type` `luks` or `native`) swap is encrypted with plain dm-crypt and a new random key on every boot (`crypt_swap` in `/etc/crypttab`), so hibernation is not possible.
* With `enable_swap_partitions: false` no swap partition is created; the other partitions keep their numbers (1, 3, 4).

_NOTE: Per OpenZFS root on ZFS recommendations, swap should not reside on ZFS partitions or zvols due to reports of deadlocks with swap. Thus `mdadm` is used for multiple device based swap configurations._

```yaml
###############################################################################
# Swap Partition Settings
###############################################################################
# Create Swap Partitions
enable_swap_partitions: true

# Swap partition size when one or two devices are used
single_or_mirror_swap_partition_size_mb: "4096"

# Swap partition size, per device, when three or more devices are used.
# They form an mdadm raid10, usable size in MB is: #devices * size_MB / 2
raidz_swap_partition_size_mb: "1024"
```

## Replacing a Disk

Before removing a disk, mark its swap partition as failed and remove it from the array, so swap keeps working in degraded state. See [Replacing a Disk](replacing-a-disk.md) for all steps.

[Back to README.md](../README.md)
