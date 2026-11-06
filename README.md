# ZFS on Root For Debian 13 Trixie

> This Role is a modified version of [reefland/ansible-zfs_on_root](https://github.com/reefland/ansible-zfs_on_root)

This Ansible role installs Debian 13 with ZFS as root filesystem and ZFSBootMenu as boot loader. It is mainly intended as base for a Proxmox VE host installed on top, but also works for a "normal" Debian host.

---

## Features

* Uses ZFSBootMenu / rEFInd / Syslinux to manage boot environments
  * rEFInd provides a graphical boot loader menu on UEFI systems
  * Syslinux provides a boot loader menu for Legacy BIOS systems
  * ZFSBootMenu provides menu driven roll-back to previous ZFS snapshots and kernels
  * Automatic snapshot of the root dataset before every `apt`/`dpkg` run
* No GRUB Boot Loader!
* Multi-disk systems: the ESP (boot) partitions form an `mdadm` mirror across all disks, and on UEFI each disk gets its own boot entry
* Multi-disk systems boot with a missing disk: the pool imports degraded and the `mdadm` arrays (ESP, swap, LVM) are started degraded after 30 seconds
* No separation of `bpool` and `rpool`, just a single `rpool` is needed
* Predefined rules for ZFS root pool types (mirror, raidz1, raidz2, multiple mirror vdevs) based on number of devices available
* Swap partitions can be enabled
  * Multi-disk swap partitions automatically setup with `mdadm` (mirror or raid10)
  * If encryption is enabled, swap is encrypted with a random key on every boot
* Optional LVM partition (e.g. for Proxmox VE `lvmthin` storage), `mdadm` based on multiple disks
* Encryption: ZFS in LUKS containers or ZFS native encryption (single encryption root), one passphrase prompt at boot
* UEFI and Legacy BIOS booting supported (both boot loaders are installed)
* Customized SSH Configuration Options
* Dropbear support for entering the passphrase remotely at boot
* Support for Apt-Cacher-NG proxy for cached packages

---

## TL;DR

* The role is intended for bare-metal systems or virtual machines booted from a Debian Live CD (it just needs SSH access to get started).
* This is for the initial installation ONLY, not for applying changes over time -- make those changes via some other playbook / change control system.
* This process uses ENTIRE disk(s) and wipes partitions on the specified disks, any existing data on these disks will be lost.
* Review `defaults/main.yml` to set the temporary root password, partition sizes, swap, encryption, network, etc.
* Builds a headless server environment.
* Not every combination of settings has been tested. If you find a problem, please open a GitHub issue in this repository, and see [Known Issues](#known-issues) for workarounds.

---

## Environments Tested

* Debian 13 / Trixie, installed from the Debian Live 13 "standard" ISO.
* A test matrix (single disk to 4 disks, UEFI and legacy BIOS, `luks` / `native` / no encryption, swap and LVM, Dropbear unlock, booting with a missing disk) runs unattended on a Proxmox VM, see [`tests/vm/README.md`](tests/vm/README.md). The results are in [`NEXT_STEPS.md`](NEXT_STEPS.md).

---

## Requirements

* [Ansible](https://www.ansible.com/) Core 2.18 or newer with the collections `community.general`, `community.crypto` and `ansible.posix`
* [Debian 13 "Trixie" Live CD](https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/), the "standard" (command-line) image is enough. A desktop image works as well; the installed system is command-line only either way.
* Memory: ZFS runs slowly with less than 2 GiB, 4 GiB or more are recommended. Running this playbook on a VPS with only 4 GiB of memory caused issues.

## Caution

* This process uses the whole physical disk
* This process is not compatible with dual-booting
* Backup your data. **Any existing data will be lost!**

---

## What is rEFInd and ZFSBootMenu?

**rEFInd** is a graphical boot manager used instead of GRUB. GRUB only supports a subset of ZFS features (and no ZFS native encryption), so it is not used at all.

![rEFInd Boot Menu Image](./docs/refind_boot_menu.png)

* Can be themed and customized as well!

**ZFSBootMenu** allows you to select which "boot environment" to use, this can be a previous ZFS Snapshot. See [Project Home Page](https://github.com/zbm-dev/zfsbootmenu) for details. The role builds ZFSBootMenu from a pinned release (`zfs_boot_menu_version` in `vars/main.yml`).

![ZFS Boot Menu Image](./docs/zfsbootmenu.png)

* Can browse, clone and promote ZFS snapshots to new boot environments.
* A snapshot of the root dataset (`rpool/ROOT/pve-1@apt_<date>`) is taken before every `apt` or `dpkg` run that installs, upgrades or removes packages. The installation itself ends with the snapshot `@base_install`.

---

## WHY use THIS?

Besides being a repeatable installation, it saves the rather cumbersome manual process of installing a Debian system with ZFS on root. With Proxmox in mind, it gives an enhanced partition layout and an encrypted root without ZFS native encryption, which brings problems with ZFS replication.

### Configurable Rules

This provides a configurable way to define how the ZFS installation will look like and allows for complex topologies.

* For example:
  * If you always want a 3 disk setup to be a _raidz_ root pool, but a 4 disk setup should use multiple _mirrored_ vdevs, you can define these defaults.
* The swap partition size can be set to one value for one or two disks and to another value (per disk) for three or more disks.
* UEFI Booting is automatically enabled and will be used when detected, it will fall back to Legacy BIOS booting when not detected.

See [Root Partition Settings](docs/root-partition-settings.md) for the partition layout.

### Optional Encryption (LUKS or ZFS Native)

The root pool can be [encrypted](docs/zfs-encryption-settings.md) with LUKS (default) or ZFS native encryption (aes-256-gcm). Swap and the optional LVM partition are encrypted as well.

* LUKS: the ZFS pool sits on LUKS containers, ZFS features such as replication are unaffected.
* ZFS native encryption: one encryption root for the whole pool, every dataset inherits it.
* The passphrase is entered once at boot in ZFSBootMenu. [Dropbear](docs/dropbear-settings.md) support can be enabled to enter it remotely via SSH.

### SSHD Configuration Settings

Some of the [SSHD configuration](docs/custom-sshd-settings.md) options can be defined to help lock down your base server image. By default, Password Authentication is disabled, Pubkey Authentication is enabled and root login is only permitted via PubKey Authentication.

### Dropbear Support

When a computer with an encrypted root pool is rebooted, someone needs to be at the console to enter the passphrase.

* You can enable the option to install [Dropbear](https://en.wikipedia.org/wiki/Dropbear_(software)), a lightweight SSH server, inside ZFSBootMenu.
* This allows you to SSH in remotely and provide the passphrase, so the machine continues to boot.
* Dropbear listens on port 222 and only accepts the SSH keys listed in `public_key_for_dropbear` (no passwords).

---

## How do I set it up

### Get the Role

Clone the repository into the roles directory of your Ansible project. The directory name is the role name used in the playbook below:

```bash
git clone https://github.com/karigeo/ansible-zfs_on_root.git roles/zfs_on_root
```

### Edit your inventory document

I use a `yaml` format inventory file, you will have to adjust to whatever format you use.

```yaml
---
###[ Define all Hosts ]########################################################
all:
  hosts:
    ...

  children:
    ###[ ZFS on Root Installs ]################################################
    zfs_on_root_install_group:
      hosts:
        testlinux01.localdomain:
          host_name: "testlinux01"
          disk_devices: ["sda", "sdb", "sdc"]

        testlinux02.localdomain:
          host_name: "testlinux02"
          disk_devices: ["sda", "nvme0n1"]

        testlinux03.localdomain:
          host_name: "testlinux03"
          disk_devices: ["vda"]
          root_partition_size: "+120G"
          disk_encryption_type: native
          ipv4:
            interfaces:
              - name: ens18
                address_type: manual
            bridges:
              - name: vmbr0
                address_type: static
                network_address: "192.168.0.13/24"
                gateway: 192.168.0.1
                bridge_ports: ["ens18"]
                vlan_aware: true
                bridge_vids: "2-4094"
            dns_nameserver: 192.168.0.1
            dns_search_domain: localdomain

      vars:
        # User created on the live CD by do_ssh.sh, and its SSH key
        ansible_user: ansible
        ansible_ssh_private_key_file: ~/.ssh/ansible

        # Define the default domain these hosts will use
        domain_name: "localdomain"

        # Define URL for Apt-Cacher-NG Package Cache
        # apt_http_proxy: "http://192.168.0.243:3142"
        # apt_https_proxy: false
```

* `zfs_on_root_install_group:` block lists the hostname(s) that you intend to boot the Live CD on and perform a ZFS on Root installation.
* Ansible connects to the same address (`ansible_host`, or the inventory name) before and after the reboot into the new system. The network configuration of the new system (`ipv4`, see [Computer Configuration Settings](docs/computer-config-settings.md#network)) must therefore give it the address the live CD had, e.g. the same static address or a DHCP reservation.

#### Inventory / Host Variables

`host_name` and `disk_devices` are prompted for if they are not set. Everything else has a default in `defaults/main.yml`.

* `host_name:` defines the name of the new system to be built. If not set, you are prompted for it (default: the first part of `ansible_host`).
* `disk_devices:` defines the names of the disk devices to use when building the ZFS pools if you know them in advance.
  * This makes reinstalls easier. Define unique configurations when needed.
  * If not set, you are prompted for it (the detected SATA/SCSI, MMC and NVMe disks are suggested; virtio disks such as `vda` must be entered explicitly).
  * Default rules will make 2 devices a mirror, 3 will use a raidz1, 4 will join two mirrored vdevs into a pool (you can redefine these)
  * Devices are referenced by `/dev/disk/by-id`, or `/dev/disk/by-path` for disks without an id (e.g. virtio disks without serial).
* `root_partition_size:` allows you to specify the partition size to be used for the root pool.
  * This is per disk device partition size (not a specification of overall pool size)
  * `0` (zero) allocates all remaining disk space
  * You can specify a specific size (positive number) such as `+120G`
  * Or state how much space not to use (negative number) such as `-512M`
* `domain_name:` under `vars:` sets the domain name that will be used for each host created. If an individual host needs a different domain name then just add a `domain_name:` under that host.
* `apt_http_proxy` and `apt_https_proxy` can be used to specify where to find an Apt-Cacher-NG instance available on your network
  * Apt-Cacher-NG will cache downloaded `apt` packages reducing your internet bandwidth needs for packages
  * The proxy is configured on the live CD and stays configured in the new system (`/etc/apt/apt.conf.d/01proxy`). An unset value becomes `false` (no proxy).
* Any setting of `defaults/main.yml` (e.g. `disk_encryption_type`, `ipv4`, `apply_dropbear_settings`) can be set per host.

---

### Edit `defaults/main.yml` to define the defaults

The `defaults/main.yml` contains most settings that can be changed.

You are defining reasonable defaults. Individual hosts that need something a little different can be set in the inventory file or you can use any other method that Ansible supports for defining variables.

#### Disable Logging Secrets

By default, secrets (passphrase, passwords) are hidden in the task output and on the summary screens. Set `no_log_secrets` to `false` to show them, if that helps troubleshooting.

```yml
# Don't log or display secrets (passphrase, passwords) when running the playbook
no_log_secrets: true
```

#### Define Temporary Root Password

This temporary root password is only used during the build process. It is expired at the end of the installation, so it has to be changed on the first login.

```yml
# Temporary root password used during the build process.
# It is expired in final_setup (must be changed on first login).
default_root_password: "root"
```

#### Installer System Check

The install steps (up to `reboot_remote`) only run on a system booted from a Debian Live CD, recognized by `boot=live` on the kernel command line. To install from another system, e.g. a rescue system, set `require_live_cd` to `false`. Note that the role still expects a Debian system with `apt` and the headers of the running kernel available.

```yml
require_live_cd: true
```

Independent of this setting, the install steps refuse to run if one of the target disks holds a filesystem mounted outside the install mount point (`/mnt`), for example the root filesystem of the running system or the live medium. See [Alternative Step by Step Installation](#alternative-step-by-step-installation) for the checks of the other steps.

### Additional Settings to Review

* Review [Computer Configuration Settings](docs/computer-config-settings.md) (boot menu, locale, network, packages)
* Review [SWAP Partition Settings](docs/swap-partition-settings.md)
* Review [Root Pool & Partition Settings](docs/root-partition-settings.md)
* Review [Disk Encryption Settings](docs/zfs-encryption-settings.md)
* Review [Custom SSHD Configuration Settings](docs/custom-sshd-settings.md)
* Review [Dropbear Settings](docs/dropbear-settings.md)

### Additional Configuration Files

There should be no reason to alter `vars/main.yml`. It defines the details to construct partitions, root pools and datasets, the pinned versions of ZFSBootMenu and its helpers, and the tag lists. If this type of information interests you, this is where you will find it... but don't change anything unless you understand what you are looking at.

Secrets (e.g. `passphrase`, `default_root_password`) can be placed in `secrets/main.yml` inside the role directory. The file is optional and not tracked by git; if it exists, it is loaded at the start of the role.

---

## How do I Run It

### Prepare the Install Environment

1. Boot the Debian Live CD on the target system:
    * Select the option <button name="button">Live</button>.
    * Standard image: log in on the console (user `user`, password `live`). Desktop image: open a terminal.
    * Connect the system to the network. Ansible later reaches the installed system at the same address, see the inventory notes above.

2. Run the helper script `do_ssh.sh`. It creates an `ansible` user account with a password and passwordless `sudo`, installs the SSH server, Python, etc.:

    ```bash
    wget https://raw.githubusercontent.com/karigeo/ansible-zfs_on_root/main/files/do_ssh.sh

    chmod +x do_ssh.sh

    ./do_ssh.sh
    ```

    * When prompted for the Ansible password, enter and confirm it. This is a temporary password, only needed to push the SSH key to the target machine. It only exists on the live CD: the `ansible` user of the new system has no password, only SSH key authentication is allowed.
    * If you can't download the script, see the [manual steps](docs/do_ssh_helper_script.md).

The Live CD Install Environment is now ready. The rest is done from the Ansible control node.

### Push your Ansible Public Key to the Install Environment

From the Ansible Control Node push your ansible public key to the Install Environment.
You will be prompted for the ansible password created within the Debian Live CD Install Environment:

```bash
ssh-copy-id -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i ~/.ssh/ansible.pub ansible@<remote_host_name>

# Expected output:
ansible@<remote_host_name> password:

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'ansible@<remote_host_name>'"
and check to make sure that only the key(s) you wanted were added.
```

The live CD creates new SSH host keys on every boot, and the installed system takes over the host keys of the live CD it was installed from. For reinstalls, remove the old `known_hosts` entry or let Ansible skip host key checking for these hosts (e.g. `ssh_args = -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no` in `ansible.cfg`).

Optionally, you can test connectivity easily to verify SSH has been configured correctly.

```bash
ansible -i inventory.yml -m ping <remote_host_name>

# Expect output to include:

remote_host_name | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

You are now ready to perform a ZFS on Root installation to this target machine.

### Fire-up the Ansible Playbook

The `playbook.yml` is a simple yaml file used to call the role, which can look like this:

```yaml
---
- name: ZFS on Root Debian Installation
  hosts: zfs_on_root_install_group
  become: true
  gather_facts: true

  roles:
    - role: zfs_on_root
      tags: [never, bootstrap]
```

The role is destructive, so it only runs when `--tags bootstrap` (everything) or one of its step tags (see below) is given. Without these tags it does nothing, even in a site playbook. The `[never, bootstrap]` tags on the role are optional, they make the intent visible.

The most basic way to run the entire ZFS on Root process and limit to an individual host as specified:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap -l <remote_host_name>
```

* [Additional Examples with Playbook Variables](docs/playbook-examples.md)

After a while, if all goes well, you will have a reasonably decent standardized base system ready to be used and modified for any other specific role (e.g. installing Proxmox VE).

---

### Alternative Step by Step Installation

As an alternative to running the entire playbook at one time, it can be run sections at a time using the ansible `tags` as defined below. This method can be used to troubleshoot issues and replay steps if you have a way of rolling back previous failures, e.g. manually or with VM snapshots.

To run just one step use its tag instead of `bootstrap`:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --extra-vars='{disk_devices: [sda, sdb], host_name: testlinux}' -l <remote_host_name> --tags="install-zfs-packages"
```

Multiple tags can be combined to run several tasks:

```text
--tags="create_pools, create_filesystems, create_datasets"
```

This is the list and order of execution for all step tags of this role:

```text
    tags:
      - install-zfs-packages
      - clear_partition_tables_from_devices
      - create_partitions
      - create_luks_containers
      - create_pools
      - create_filesystems
      - create_datasets
      - config_system
      - install_zfs
      - config_boot_fs
      - install_refind
      - install_syslinux
      - install_zfsbootmenu
      - config_swap
      - system_tweaks
      - first_boot_prep
      - unmount_chroot
      - reboot_remote
      - localization
      - install_dropbear
      - config_lvm
      - final_setup (contains disable_ipv6 and update_sshd_settings)
      - restart_remote_final
```

`disable_ipv6` and `update_sshd_settings` can also be run on their own. `confirm_defaults` is the settings summary shown before the run (see [Skipping Tags](#skipping-tags)).

Helper tasks, basic sanity checks and mandatory tasks are tagged `always` and run with every tag: reading configuration files, prompting for missing values, setting variables, etc. There is nothing special you need to do.

NOTE: `config_system` starts on the live CD (debootstrap, chroot preparation) and continues inside the chroot. The steps from `config_system` to `first_boot_prep` run inside the chroot (via SSH port 8922) and need the live CD environment prepared by the previous steps. The steps from `localization` on run on the installed system after the first reboot.

Each group of steps starts with a check that stops the run unless the target is where these steps belong, so a step tag given for the wrong system fails before anything is changed:

| Steps | Must run on | Checked |
|-------|-------------|---------|
| `install-zfs-packages` to `config_system`, `unmount_chroot`, `reboot_remote` | Live CD | `boot=live` on the kernel command line (see `require_live_cd`), not in a chroot, no target disk in use outside `/mnt` |
| `config_system` to `first_boot_prep` | chroot of the new system | the Live CD checks, the root dataset mounted at `/mnt`, port 8922 lands in a chroot of it on the same running kernel |
| `localization` to `restart_remote_final` | Installed system | booted from the root dataset, not in a chroot |

For example, `--tags clear_partition_tables_from_devices` against the installed system fails at the check instead of wiping its disks.

### Grouping Tags

A reasonable way to build a system in stages using a group of tags instead of calling them individually:

```text
--tags="install-zfs-packages, clear_partition_tables_from_devices, create_partitions, create_luks_containers, create_pools"
--tags="create_filesystems, create_datasets, config_system, install_zfs"
--tags="config_boot_fs, install_refind, install_syslinux"
--tags="install_zfsbootmenu, config_swap, system_tweaks, first_boot_prep"
--tags="unmount_chroot, reboot_remote"
--tags="localization, install_dropbear, config_lvm, final_setup, restart_remote_final"
```

### Skipping Tags

Specific tags can also be skipped. For example, if you do not wish to see the manual confirmation page each time and would rather the playbook just execute directly, use:

```text
--tags bootstrap --skip-tags="confirm_defaults"
```

---

## Known Issues

* Nothing happens after 1st reboot? See if [UEFI BIOS Bugs / Glitches / Issues](./docs/uefi-bugs-issues.md) helps.

---

## More about Root Pool using Mirrored vdev Process

Here is a brief [overview with additional information](docs/root-pools-multi-mirrored-vdevs.md) about root pools built from multiple mirrored vdevs.

---

## Emergency chroot Recovery

If your system is unable to boot, then boot from the Debian Live CD to create a `chroot` environment where you can decrypt and mount your ZFS pools, mount boot partitions and have an interactive shell to inspect, troubleshoot, apply updates, etc. You should be comfortable with the [Emergency chroot Recovery](./docs/chroot-recovery.md) process.

---

## Replacing a Disk

On multi-disk systems every disk holds a member of the root pool and of the `mdadm` arrays (ESP, swap, LVM). See [Replacing a Disk](docs/replacing-a-disk.md) for what needs to be done, and mark the old partitions as **failed** before removing the disk.
