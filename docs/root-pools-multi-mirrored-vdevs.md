# Root Pools Built with Multiple Mirrored Vdevs

[Back to README.md](../README.md)

## Why Use Multiple Mirrored Vdevs

The `raidz` type pools add space without adding performance. The speed of read and writes tend to be limited by the speed of the slowest device in the pool.  Adding more devices does not provide you with higher IOPS.  Large number of devices in a `raidz` pool with low IOPS can take days or weeks to resilver a drive should it need to be replaced.

Using multiple mirror vdevs provides much higher performance than raidz vdevs and faster resilver. An all-mirrors pool is easier to extend and, with recent zfs versions, even to shrink (vdev removal is supported).

### Example Scenario

* If you defined 6 devices for this script to use and specified type `mirror`, the `root` pool initially will be constructed as a 2 device mirror.  (This 1st mirrored vdev pair creates the `root` pool).
* The script will then process all remaining devices, 2 at a time, to create each additional mirrored vdev pair.  
* Each mirrored vdev pair is then attached to the existing `root` pool which expands the pool size by the size of the mirror.

### Device Pair Order

Internally the role references devices by the `/dev/disk/by-id` (or `/dev/disk/by-path`) device path. Devices are paired in the order given in `disk_devices`: the 1st with the 2nd, the 3rd with the 4th, etc.

You can experiment with providing an alternate order two different ways. Using Ansible command line parameter `--extra-vars` such as:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{disk_devices: [sda, sdc, sdb, sdd]}'

```

Or perhaps a better way using the inventory file to provide this:

```yml
[zfs_on_root_install_group]
testlinux.example.com  host_name="testlinux" disk_devices='["sda", "sdc", "sdb", "sdd"]'
```

### Mismatched Device Sizes

* If your devices are of difference sizes you will want to make sure that each pair such as [ `sda` / `sdb` ] are close in size to maximize useable disk space. The mirrored vdev will be the size of the smaller device, any space remaining on the larger disk device will remain unused... for now. If you pair a 4TB and 6TB device together, the mirrored vdev will be 4TB and the other 2TB will be unavailable... for now.

* It is technically possible replace the smaller device with a larger one later on, recreate the mirror and expand the vdev to now use the previously unused space.  But again, the mirror can only be as large as the smallest device in the pair.  Doing this is outside the scope of this project.

* Each mirrored vdev pair can be of different sizes.  They do not need to match existing mirror pair sizes.  For example you can have a pair of 4TB and a pair of 6TB devices to create a 10TB root pool.  ZFS will attempt to fill each drive proportionally to maintain a reasonably equal amount of free space on each vdev pair. In this example, a 1MB file would place about 40% on the 4TB pair and 60% on the 6TB pair. This introduces an imbalance and is magnified by the size difference between pairs and the number of pairs.  It is suggested to keep all vdev pairs close in size, but not a requirement.

### Expanding the Root Pool

* If the root pool runs low on space, it is possible to attach additional mirrored vdev pairs to the pool (outside the scope of this project).  Again, be aware of the imbalance this creates.  ZFS will greatly prefer to write to this empty vdev pair and only write a little to the other vdevs attempting to equalize free space.  This imbalance can become a bottleneck.  Unfortunately ZFS has no native way to re-balance how data is distributed across drives.

* If the imbalances described above bothers you, then consider options where all the data is moved somewhere else (external USB or network server). Delete all the data to free up as much space as possible and copy all the data back.  Again, ZFS will always try to balance out available space across the vdevs.

[Back to README.md](../README.md)
