# ZFS on Root For Debian 13 Trixie

> This Role is a modified version of [reefland/ansible-zfs_on_root](https://github.com/reefland/ansible-zfs_on_root)

This Ansible role is used to setup / bootstrap a Debian 13 system with ZFS as root filesystem and ZFSBootMenu as Bootloader. It is mainly intended as base for a Proxmox VE host installed on top, but also works for a "normal" Debian host.

_NOTE: This Ansible role is not structured as rigid as a typical Ansible role should be. Tips and suggestions on how to improve this are welcomed._

---

## Features:

* Uses ZFSBootMenu / rEFInd / Syslinux to manage boot environments
  * rEFInd provides a graphical boot loader menu on UEFI systems
  * Syslinux provides a boot loader menu for Legacy BIOS systems
  * ZFSBootMenu provides menu driven roll-back to previous ZFS snapshots and kernels
  * Automatic snapshot creation upon apt/dpkg install or remove
* No GRUB Boot Loader!
* All ESP (boot) partitions are an `mdadm` mirror across all devices, each disk gets its own UEFI boot entry
* Multi-disk systems boot with a missing disk: the pool imports degraded and the `mdadm` arrays (ESP, swap, LVM) are started degraded after 30 seconds
* No separation of `bpool` and `rpool`, just a single `rpool` is needed
* Predefined rules for ZFS root pool types (mirror, raidz1, raidz2, multiple mirror vdevs) based on number of devices available
* Swap partitions can be enabled
  * Multi-disk swap partitions automatically setup with `mdadm` (mirror or raid10)
  * If encryption is enabled, swap is encrypted with a random key on every boot
* Optional LVM partition (e.g. for Proxmox VE `lvmthin` storage), `mdadm` based on multiple disks
* Encryption: ZFS in LUKS containers or ZFS native encryption (single encryption root), one passphrase prompt at boot
* UEFI and Legacy Booting supported (can even switch between them)
* Customized SSH Configuration Options
* Dropbear support for entering the passphrase remotely at boot
* Support for Apt-Cacher-NG proxy for cached packages

---

## TL;DR

* This is a WORK IN PROGRESS:
  * Not every combination has been tested. If you find a problem, please open a GitHub issue in this repository.
  * Review [known issues](README.md#known-issues) for workarounds.

* This Ansible based process is intended to be used against bare-metal systems or virtual machines (just needs SSH access to get started).
  * This is intended for initial installation ONLY, this is not for applying changes over time -- you should make those changes via some other playbook / change control system.
* This process uses ENTIRE disk(s) and wipes partitions on the specified disks, any existing data on these partitions on the target system will be lost.
* Review the `defaults/main.yml` to set temporary passwords, basic rules on partition sizes, swap partitions, encryption, network, etc.
* Builds a headless server environment.

---

## Environments Tested

* Debian 13 / Trixie

---

## Requirements

* [Ansible](https://www.ansible.com/) Core 2.18 or newer with the collections `community.general`, `community.crypto` and `ansible.posix`
* [Debian 13 "Trixie" Live CD](https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/) (Desktop - DO NOT use standard images)
  * _NOTE: the installed system is command-line only, even when using the desktop image._
* Computers that have less than 2 GiB of memory run ZFS slowly. 4 GiB of memory is recommended for normal performance in basic workloads.
* Besides that, I had issues running this playbook on a VPS with only 4GiB of memory

## Caution

* This process uses the whole physical disk
* This process is not compatible with dual-booting
* Backup your data. **Any existing data will be lost!**

---

## What is rEFInd and ZFSBootMenu?

**rEFInd** is a graphical boot manager replacement used instead of GRUB. GRUB is not ZFS aware.

![rEFInd Boot Menu Image](./docs/refind_boot_menu.png)

* Can be themed and customized as well!

**ZFSBootMenu** allows you to select which "boot environment" to use, this can be a previous ZFS Snapshot. See [Project Home Page](https://github.com/zbm-dev/zfsbootmenu) for details. The role builds ZFSBootMenu from a pinned release (`zfs_boot_menu_version` in `vars/main.yml`).

![ZFS Boot Menu Image](./docs/zfsbootmenu.png)

* Can browse, clone and promote ZFS snapshots to new boot environments.
* Snapshots will automatically be taken before each `apt` or `dpkg` update.

---

## WHY use THIS?

Besides being handy to have a repeatable installation possibility the manual process of installing a Debian system with ZFS on root is rather cumbersome. With Proxmox in mind, this gives the ability to have an enhanced partition layout and also be able to have an encrypted root without using the ZFS native encryption, which brings problems with ZFS replication.

### Configurable Rules

This provides a configurable way to define how the ZFS installation will look like and allows for complex topologies.

* For example:
  * If you always want a 3 disk setup to be a _raidz_ root pool, but a 4 disk setup should use multiple _mirrored_ vdev based root pool you can define these defaults.
* The size of swap partitions can be defined to a standard value for single device and mirrored setups or a different value for raidz setup.
* UEFI Booting is automatically enabled and will be used when detected, it will fall back to Legacy BIOS booting when not detected.

See [Root Partition Settings](docs/root-partition-settings.md) for the partition layout.

### Optional Encryption (LUKS or ZFS Native)

The root pool can be [encrypted](docs/zfs-encryption-settings.md) with LUKS (default) or ZFS native encryption (aes-256-gcm). Swap and the optional LVM partition are encrypted as well.

* LUKS: the ZFS pool sits on LUKS containers, ZFS features such as replication are unaffected.
* ZFS native encryption: one encryption root for the whole pool, every dataset inherits it.
* The passphrase is entered once at boot in ZFSBootMenu. [Dropbear](docs/dropbear-settings.md) support can be enabled to enter it remotely via SSH.

### SSHD Configuration Settings

Some of the [SSHD configuration](docs/custom-sshd-settings.md) options can be defined to help lock down your base server image. For example, Password Authentication will be disabled, Pubkey Authentication will be enabled, Root login will only be permitted via PubKey Authentication.

### Dropbear Support

When a computer with an encrypted root pool is rebooted, someone needs to be at the console to enter the passphrase.

* You can enable the option to install [Dropbear](https://en.wikipedia.org/wiki/Dropbear_(software)) to provide a lightweight SSH server inside ZFSBootMenu during the boot process.
* This allows you to remotely SSH to the console to provide the passphrase to allow the machine to continue to boot.
* Dropbear listens on port 222.
* ECDSA or ED25519 keys can be used to connect to Dropbear (no passwords allowed).

---

## How do I set it up

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
        # Define the default domain these hosts will use
        domain_name: "localdomain"

        # Define URL for Apt-Cacher-NG Package Cache
        # apt_http_proxy: "http://192.168.0.243:3142"
        # apt_https_proxy: false
```

* `zfs_on_root_install_group:` block lists the hostname(s) that you intend to boot the Live CD on and perform a ZFS on Root installation.

#### Inventory / Host Variables

All of these are optional, if not provided you will be prompted to enter values if needed.

* `host_name:` defines the name of the new system to be built, if set here you will not be prompted for it.
* `disk_devices:` defines the names of the disk devices to use when building the ZFS pools if you know them in advance.
  * This makes reinstalls easier. Define unique configurations when needed.
  * When this is set you will not be prompted.
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
* Any setting of `defaults/main.yml` (e.g. `disk_encryption_type`, `ipv4`, `apply_dropbear_settings`) can be set per host.

---

### Edit `defaults/main.yml` to define the defaults

The `defaults/main.yml` contains most settings that can be changed.

You are defining reasonable defaults. Individual hosts that need something a little different can be set in the inventory file or you can use any other method that Ansible supports for defining variables.

#### Disable Logging Secrets

Ansible tasks that reference secrets (password or passphrase) may show them on the screen as well as settings summary screens. Showing passwords can be enabled if that would help troubleshooting.

```yml
# Don't log or display secrets (passphrase, passwords) when running the playbook
no_log_secrets: true
```

#### Define Temporary Root Password

This temporary root password is only used during the build process. It is expired at the end of the installation, so it has to be changed on the first login.

```yml
# Temporary root password used during the build process.
# It is expired in final_setup (must be changed on first login).
default_root_password: "change!me"
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

There should be no reason to alter the configuration file `vars/main.yml` which defines all the details and flags to construct partitions, root pools, and how all the datasets will be created. If this type of information interests you, this is where you will find it... but don't change anything unless you understand what you are looking at.

Secrets can be placed in `secrets/main.yml` (not tracked by git), it is loaded at the start of the role.

---

## How do I Run It

### Prepare the Install Environment

1. Boot the Debian Live CD:
    * Select option <button name="button">Live</button>.
    * Connect your system to the internet as appropriate (e.g. join your Wi-Fi network).
    * Open a terminal within the Live CD environment - press <kbd>Ctrl</kbd> <kbd>Alt</kbd>-<kbd>T</kbd>.

2. Install and start the OpenSSH server in the Live CD environment (see helper script below):

#### Fetch Helper Script

The helper script will perform many steps for you such as create an `ansible` user account, define a password for that account, grant the `ansible` account `sudo` privileges, install SSH server, python, etc.

##### Option 1 - Proper Way to Run Helper Script

```bash
wget https://raw.githubusercontent.com/karigeo/ansible-zfs_on_root/master/files/do_ssh.sh

chmod +x do_ssh.sh

./do_ssh.sh
```

* When prompted for the Ansible password, enter and confirm it. This will be a temporary password only needed just to push the SSH Key to the target machine. The Ansible password will be disabled and only SSH authentication will be allowed.

The Live CD Install Environment is now ready. Nothing else you need to do here. The rest is done from the Ansible Control node.

#### If Helper Script is not Available

* [Manual steps](docs/do_ssh_helper_script.md) if you are unable to access "do_ssh.sh" Help Script.

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

As an alternative to running the entire playbook at one time, it can be run sections at a time using the ansible `tags` as defined below. This method can be used to troubleshoot issues and replay steps if you have a way of rolling back previous failures. Failures can be rolled back either manually or via snapshots in Virtualbox or equivalent.

To run just one step use its tag instead of `bootstrap`:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --extra-vars='{disk_devices: [sda, sdb], host_name: testlinux}' -l <remote_host_name> --tags="install-zfs-packages"
```

Multiple tags can be combined to run several tasks:

```text
--tags="create_pools, create_filesystems, create_datasets"
```

This is the list and order of execution for all tags defined for this role:

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

Helper tasks, basic sanity checks and mandatory tasks are already marked as `always` and will always be processed to setup the base ansible working environment reading configuration files, setting variables, etc... nothing special you need to do.

NOTE: The steps `config_system` to `first_boot_prep` run inside the chroot (via SSH port 8922), they need the live CD environment prepared by the previous steps. The steps from `localization` on run on the installed system after the first reboot.

Each group of steps starts with a check that stops the run unless the target is where these steps belong, so a step tag given for the wrong system fails before anything is changed:

| Steps | Must run on | Checked |
|-------|-------------|---------|
| `install-zfs-packages` to `config_system`, `unmount_chroot`, `reboot_remote` | Live CD | `boot=live` on the kernel command line (see `require_live_cd`), not in a chroot, no target disk in use outside `/mnt` |
| `config_system` to `first_boot_prep` | chroot of the new system | the Live CD checks, the root dataset mounted at `/mnt`, port 8922 lands in a chroot of it on the same running kernel |
| `localization` to `restart_remote_final` | Installed system | booted from the root dataset, not in a chroot |

For example, `--tags clear_partition_tables_from_devices` against the installed system fails at the check instead of wiping its disks. The checks are tagged `always`, so `--skip-tags always` would skip them.

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
* `mdadm` error [super1.x cannot open / Device or resource busy](./docs/mdadm-error-cannot-open.md) during `config_boot_fs` tag processing

---

## More about Root Pool using Mirrored vdev Process

This topology is not available from the Debian installer and is not covered by the [OpenZFS HowTo method](https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/index.html).

Here is a brief [overview with additional information](docs/root-pools-multi-mirrored-vdevs.md).

---

## Helper Scripts

* [do_ssh.sh](docs/do_ssh_helper_script.md) - Makes a LiveCD environment accessible to Ansible via SSH.

---

## Emergency chroot Recovery

If your system is unable to boot, then boot from the Debian Live CD to create a `chroot` environment where you can decrypt and mount your ZFS pools, mount boot partitions and have an interactive shell to inspect, troubleshoot, apply updates, etc. You should be comfortable with the [Emergency chroot Recovery](./docs/chroot-recovery.md) process.

---

### Replacing a Swap Device

NOTE: `mdadm` is used to create mirrored or raid10 swap arrays. If you will be replacing a drive then you should mark its swap partition as **failed** before removing it from the system, see [Swap Partition Settings](docs/swap-partition-settings.md#replacing-a-disk).
