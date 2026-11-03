# CLAUDE.md

Guidance for Claude Code (and other agents) working on this repository.

## What This Is

An Ansible role that installs Debian 13 (Trixie) on ZFS root from a Debian Live CD: it wipes the given disks, partitions them, optionally encrypts (LUKS or ZFS native), creates the root pool and datasets, debootstraps Debian, installs ZFSBootMenu (booted by rEFInd on UEFI, syslinux on legacy BIOS) and finalizes the system. Main purpose: base system for a later Proxmox VE installation (datasets `var/lib/vz`, `etc-pve`, `rpool/data`, LVM thin pool `pve/data`), but also usable for a plain Debian host. **Initial installation only, destructive**, not for ongoing configuration management.

- Fork of [reefland/ansible-zfs_on_root](https://github.com/reefland/ansible-zfs_on_root) (Ubuntu), adapted to Debian/PVE.
- Sibling role: `../ansible_deb_btrfs-on-root` (BTRFS + GRUB, evolved from this role). Fixes often apply to both; compare before porting.

## Running the Role

`playbook.yml`, `inventory.yml`, `ansible.cfg` and `secrets/*.yml` are gitignored (local per deployment).

```bash
# Full run (the role does nothing without one of its tags)
ansible-playbook -i inventory.yml ./playbook.yml -l <host> --tags bootstrap

# With extra vars
ansible-playbook -i inventory.yml ./playbook.yml -l <host> --tags bootstrap \
  --extra-vars='{disk_devices: [sda, sdb], host_name: "myhost", passphrase: "mySecr3tPa55"}'

# Single steps (the "always" checks of 01/02 run as well)
ansible-playbook -i inventory.yml ./playbook.yml -l <host> --tags "create_pools,create_filesystems"

# Skip the confirmation dialog
--tags bootstrap --skip-tags confirm_defaults
```

Requirements: ansible-core >= 2.18 (`ansible.builtin.mount_facts`), collections `community.general`, `community.crypto`, `ansible.posix`. The target runs the Debian Live CD prepared with `files/do_ssh.sh` (user `ansible`, sudo, sshd, python3-pexpect).

There are no automated tests. Useful local checks:

- `ansible-lint --offline -p .` (remaining warnings are mostly line length/alignment)
- YAML parse of all files, `ansible-playbook --syntax-check` with a scratch playbook (includes are dynamic, so this only checks `tasks/main.yml`)
- Render templates / var expressions with a scratch playbook against `localhost` that loads `vars/main.yml` and `defaults/main.yml` via `vars_files` (pass overrides with `-e`, play vars lose against `vars_files`)

Real verification needs a VM (e.g. on Proxmox) booted from the Debian Live ISO.

## Architecture

### Tag gating (`tasks/main.yml`)

The includes are tagged `always` and gated with `when: ansible_run_tags | intersect(zfs_on_root_tags) | length > 0`. Included tasks get the `bootstrap` tag via `apply`. Result: without `--tags bootstrap` or a step tag the role is inert (safe in a site playbook), `--tags <step>` works and `--skip-tags` works per task. **When adding a new tag to a task file, add it to `zfs_on_root_tags` in `vars/main.yml`**, otherwise the role is not activated by it.

### Three phases

1. **Live CD** (`01`–`09_0`, ansible_port 22): checks/prompts, sshd on the live CD also listens on 8922 with `ChrootDirectory /mnt` (`03`), wipe disks, partition, LUKS, `zpool create -R /mnt`, datasets, debootstrap, bind mounts, `ansible` user in the chroot (same UID and SSH key as on the live CD).
2. **chroot** (`09_1`–`13`, `ansible_port: 8922` set on the include): Ansible connects to the live system's sshd on port 8922 and lands directly in the chroot. Tasks use normal paths (`/etc/...`), not `/mnt/...`. Kernel/ZFS, ESP, rEFInd, syslinux, ZBM, swap, final initramfs.
3. **Installed system** (`15`–`20`, port 22): unmount/export, reboot into the new system, localization, dropbear (ZBM image), LVM, final setup, final reboot.

### Files

- `defaults/main.yml`: user-facing settings (passwords, locale, network `ipv4.interfaces`/`ipv4.bridges`, swap, `disk_encryption_type`, pool/partition sizes, `set_root_pool_type`, sshd, dropbear).
- `vars/main.yml`: internal constants and derived values (partition numbers/flags, `root_pool_devices`, `luks_root_mapper_names`, `swap_device`, `lvm_device`, pool/dataset options, pinned versions of ZBM/zbm-luks-unlock/dracut-crypt-ssh, `zfs_on_root_tags`). Many are lazy expressions on `disk_by_id`, which is built in `01_basic_checks.yml`.
- `secrets/main.yml`: loaded first via `include_vars` (gitignored).
- `docs/`: user documentation per topic; keep it in sync with `defaults/main.yml`.

### Disk layout and devices

- `disk_devices` (e.g. `sda`) becomes `disk_by_id`: `/dev/disk/by-id/...`, falling back to `/dev/disk/by-path/...` (virtio disks without serial). By-path names contain `:`, which is stripped for device-mapper names.
- Partitions per disk: 1 ESP (EF00, legacy-BIOS-bootable attribute for syslinux), 2 swap, 3 ZFS root (BF00, or 8309 for LUKS), 4 optional LVM.
- Multi-disk mdadm arrays: ESP mirror `/dev/md/BOOT_EFI` (metadata 1.0, so firmware sees plain FAT32), swap `/dev/md/swap` (mirror for 2 disks, raid10 for 3+), LVM `/dev/md/lvm` (mirror for 2 disks, raid5 for 3+). ARRAY lines go to `/etc/mdadm/mdadm.conf` via `blockinfile` (`13`, `18_5`).
- Root pool: one vdev of `root_pool_type`, or mirrored vdev pairs for 4+ disks of type `mirror` (`06_create_pools.yml`).

### Encryption (`disk_encryption_type`)

- `luks`: one LUKS container per root partition (`crypt_<disk>_root`), pool built on the mappers. ZBM unlocks them with the [zbm-luks-unlock](https://github.com/agorgl/zbm-luks-unlock) hooks (prompt). The booted system unlocks them again via `/etc/crypttab` (`initramfs` option) with `/etc/cryptsetup-keys.d/<pool>.key` embedded in the initramfs (`KEYFILE_PATTERN`, `UMASK=0077`).
- `native`: pool-level encryption root (`-O encryption ... keylocation=file:///etc/zfs/<pool>.key`). The keyfile is written on the live CD before `zpool create`, copied into the chroot, `org.zfsbootmenu:keysource` points to the root dataset, and the initramfs-tools hook `zfs-native-key` embeds the keyfile. No unencrypted datasets are possible in the pool.
- Both: swap is plain dm-crypt with a random key (`crypt_swap`), and the LVM partition is a LUKS container (`crypt_lvm`) unlocked after root is mounted (keyfile on root, not in the initramfs).

### Boot chain

UEFI firmware → rEFInd (`/boot/efi/EFI/refind`, custom menu entry; on multi-disk installs one UEFI boot entry per disk) or syslinux (legacy BIOS, `/boot/efi/syslinux`, config generated by ZBM's `syslinux-update.sh` post hook) → ZFSBootMenu components (`/boot/efi/EFI/zfsbootmenu/vmlinuz-bootmenu` + `initramfs-bootmenu.img`, built from source with dracut) → kexec into the Debian kernel and its initramfs-tools initramfs.

The host uses **initramfs-tools** (`update-initramfs`). **dracut** is only used to build the ZBM image (`generate-zbm`, config in `/etc/zfsbootmenu/`).

### Dropbear

`18_enable_dropbear.yml` adds the dracut-crypt-ssh module (dropbear, port 222, host keys converted from OpenSSH ECDSA/ED25519) and the network config (`/etc/cmdline.d/dracut-network.conf`) to the **ZBM image only**. `dropbear-bin` provides the binaries; there is no dropbear service and no `dropbear-initramfs` on the host.

## Gotchas

- **Handlers run with play/host vars**, not with the include's `ansible_port: 8922`. A handler notified from a chroot-phase task would run against the live CD. Use explicit tasks in the chroot phase.
- Don't set `ansible_port` via `--extra-vars`: it would override the chroot port 8922.
- The `command` module does not do shell redirects or pipes (`echo ... >> file` silently writes nothing). Use `shell`, or better a module (`lineinfile`, `blockinfile`, `ansible.posix.mount`, `community.general.crypttab`).
- `ternary()` evaluates both branches: don't index possibly empty lists inside it (use `if/else` in templates).
- In Jinja string literals, backslash sequences are unescaped (`'\1'` becomes `chr(1)`); avoid regex backreferences there.
- After changes that affect the ZBM image (dropbear, ZBM hooks, `/etc/zfsbootmenu/dracut.conf.d/*`) run `generate-zbm`. After changes to crypttab, mdadm.conf, keyfiles or initramfs hooks run `update-initramfs -u -k all`.
- The ESP is FAT32: `mode` on files/directories there has no effect (annotated with `noqa: risky-file-permissions`).
- `dracut.conf.d/zfsbootmenu-luks-uuids.conf` (from zbm-luks-unlock) holds bare UUIDs but is sourced as shell by dracut. The resulting "command not found" noise in `generate-zbm` output is expected.

## Conventions

- FQCN module names, `ansible_facts['...']` instead of bare fact variables (`ansible_nodename` etc.).
- Task blocks carry a step tag and (except the reboot/notice blocks) the `ansible_facts['nodename'] != "localhost"` guard; sanity checks/prompts are tagged `always`.
- `changed_when` on `command`/`shell` tasks (`false` for read-only commands).
- Secrets: `no_log: "{{ no_log_secrets | default(true) | bool }}"` on tasks that handle `passphrase`/passwords.
- External sources are pinned (`vars/main.yml`): bump the version/commit deliberately and check the ZBM config/hooks still match.
- No commented-out code; remove unused variables, templates and task files instead of leaving them around. Keep `README.md`/`docs/` in sync with `defaults/main.yml` and the tag list.
- Commit messages: short imperative subject, body explaining why.
