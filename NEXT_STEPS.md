# Next Steps

Status after the review/cleanup of 2026-11-03 (commits `825753f`..`7776666` on `dev-deb13`, not pushed). All changes are checked only statically (ansible-lint, YAML parse, syntax check, template/variable test renders). **Nothing has run on a real machine yet.**

## 1. Before the first test run

- [ ] Local `playbook.yml` (gitignored): fix the role path (`/Users/simon/Ansible/ansible-zfs_on_root` → `/Users/simon/Ansible/homelab/roles/ansible-zfs_on_root` or the role name) and add `tags: [never, bootstrap]` to the role (optional, the role is inert without its tags anyway).
- [ ] Runs now need `--tags bootstrap` (or a step tag, see README).
- [ ] Local `inventory.yml` (gitignored): convert `ipv4.iface` / `ipv4.bridge` to the current `ipv4.interfaces` / `ipv4.bridges` lists (see `defaults/main.yml`). `public_key_for_dropbear` must be a list of keys, not a path.
- [ ] The test VM uses `vda`: virtio disks without serial now resolve via `/dev/disk/by-path`. Optionally set a serial on the Proxmox VM disk to get a by-id name.

## 2. Test matrix

Run each case on a Proxmox VM booted from the Debian 13 Live ISO (prepared with `files/do_ssh.sh`). Every run wipes the VM disks.

| # | Disks | Firmware | Encryption | Swap / LVM | Main focus |
|---|-------|----------|------------|------------|------------|
| 1 | 1 | UEFI (OVMF) | `luks` (default) | swap + LVM | default path, LUKS unlock via ZBM hooks, crypttab keyfile, LVM LUKS after root |
| 2 | 1 | UEFI | `native` | swap + LVM | new pool-level encryption root, keysource, initramfs key hook, single prompt |
| 3 | 1 | UEFI | `none` | swap + LVM | unencrypted swap fstab entry (was broken), single-disk LVM `pvs` (was broken) |
| 4 | 2 | UEFI | `luks` | swap + LVM | ESP mdadm mirror, swap mirror, LVM mirror, mdadm.conf, one UEFI boot entry per disk |
| 5 | 3 | UEFI | `luks` or `none` | swap + LVM | raidz pool, swap raid10, LVM raid5 |
| 6 | 4 | UEFI | `none` | swap | mirrored vdev pairs (`zpool add` loop) |
| 7 | 1 | legacy BIOS (SeaBIOS) | `luks` | swap | syslinux boot, no efivars, rEFInd moved from `EFI/BOOT` |
| 8 | 1 | UEFI | any | – | step tags: `--tags create_pools` runs only that step + checks; `--tags bootstrap --skip-tags confirm_defaults`; untagged run does nothing |

Optional: 4 disks with `set_root_pool_type: {4: raidz2}` (pool creation for 4+ non-mirror disks was broken before).

### Checks after each run

- [ ] Boots without intervention except **one** passphrase prompt (encrypted cases).
- [ ] Dropbear: `ssh -p 222 root@<host>` at boot, `zbm`, passphrase, boots (cases 1, 2, 7).
- [ ] `zpool status`, `zfs list`; native: `zfs get encryption,encryptionroot,keystatus -r rpool` (all datasets share encryption root `rpool`, keys available).
- [ ] `lsinitramfs /boot/initrd.img-$(uname -r) | grep -E 'rpool.key|cryptsetup-keys'` (native: `etc/zfs/rpool.key`; luks: only `rpool.key`, not `pve.key`); image permissions `ls -l /boot/initrd.img-*` (0600).
- [ ] `cat /proc/mdstat` and the `# BEGIN ANSIBLE MANAGED ARRAYS` block in `/etc/mdadm/mdadm.conf` (multi-disk).
- [ ] `swapon --show`, `cat /etc/fstab /etc/crypttab` (no duplicate entries, swap present).
- [ ] `vgs`, `lvs` (thin pool `pve/data`), `lsblk` (`crypt_lvm` opened after boot when encrypted).
- [ ] `efibootmgr -v` (multi-disk UEFI: one `rEFInd <disk-id>` entry per disk); optionally remove one disk and boot.
- [ ] `ifup --no-act -a` (no "misplaced option"), `cat /etc/hosts /etc/resolv.conf`.
- [ ] `sshd -T | grep -iE 'passwordauth|permitroot|pubkey|usepam'` and `/etc/ssh/sshd_config.d/50-zfs_on_root.conf`.
- [ ] `python3 -c 'import pexpect'` works; `/usr/lib/python3*/EXTERNALLY-MANAGED` still exists.
- [ ] No dropbear service on the host: `systemctl status dropbear` (unit not found).
- [ ] `zfs list -t snapshot` (`@base_install`, apt snapshots after `apt install`).
- [ ] Rerun a step tag (e.g. `--tags config_swap`) on the installed system: no duplicate fstab/crypttab entries.

## 3. Noticed but left unchanged (possible later work)

Found during the review, deliberately not changed because they alter boot behaviour or need a decision. Verify on a VM before changing.

### 3.1 rEFInd never uses `refind_linux.conf`

- Where: `tasks/12_3-install_refind.yml` (template `refind_linux.conf.j2` copied to `{{ zfs_boot_menu_path }}`, `dont_scan_dirs` set from `refind_no_scan_dirs` in `defaults/main.yml`, custom `menuentry "ZFSBootMenu"`).
- What: `refind_no_scan_dirs` excludes the ZBM directory (`EFI/zfsbootmenu`), so rEFInd does not auto-detect the ZBM kernel there, and `refind_linux.conf` (which only applies to auto-detected kernels) is never read. The custom menu entry has `loader` and `initrd` but no `options` line, so ZBM boots without the intended command line: `zbm.prefer=<pool> zbm.import_policy=hostid zbm.set_hostid zbm.timeout=20 ro loglevel=0`. ZBM falls back to its defaults (e.g. the pool's `bootfs`, timeout 10 s). It works, but not as configured.
- Options:
  1. Add `options "zbm.prefer=... ro loglevel=0"` to the custom menu entry and delete `refind_linux.conf.j2` + its task (one source of truth). Decide on `zbm.timeout` (20 s may be too long), and whether `zbm.import_policy=hostid zbm.set_hostid` are wanted (`spl_hostid` is already set per boot environment via `org.zfsbootmenu:commandline`).
  2. Drop the custom menu entry and `dont_scan_dirs`, and let rEFInd auto-detect ZBM with `refind_linux.conf` (loses the custom icon/title).
  3. Keep as is and only delete the unused template.
- Related: the ZBM config (`templates/zfsbootmenu_config.yaml.j2`) has `Kernel: CommandLine: zbm.prefer=<pool> ro loglevel=0`, which only applies to EFI bundles (disabled, `EFI: Enabled: false`). The syslinux entry generated by `syslinux-update.sh` should be checked the same way.

### 3.2 `rd.break` on the dropbear network command line

- Where: `tasks/18_enable_dropbear.yml`, both "Create file /etc/cmdline.d/dracut-network.conf" tasks (DHCP and static) end with `rd.break`. The line goes into the ZBM image (`install_optional_items` in `dracut_dropbear.conf.j2`).
- What: `rd.break` tells dracut to drop to a shell at the end of the initramfs. It comes from upstream (Ubuntu era) and was kept through `e5d589b` / `06cca0c`. In the ZBM image it may be what makes the dropbear session land in the "ZFSBootMenu initramfs shell" (banner: enter `zbm`), or it may be a leftover with no effect.
- To check: boot with and without `rd.break` (edit `/etc/cmdline.d/dracut-network.conf`, `generate-zbm`) and compare console and dropbear behaviour. Remove it if ZBM and dropbear work the same without it; otherwise document why it is needed.

### 3.3 Automatic disk detection skips virtio disks

- Where: `lsblk_device_types: "8,179,259"` in `vars/main.yml`, used by `lsblk_device_command` / `lsblk_device_detail_command` for the disk prompt in `tasks/01_basic_checks.yml` (only when `disk_devices` is not set).
- What: virtio-blk (`vda`) has a dynamically assigned major number (often 252-254), so it is neither listed nor suggested. Device-mapper also uses a dynamic major, so simply adding 252/253 could list dm devices.
- Options: select by `lsblk -ndo name,type,ro` with `TYPE == "disk"` (and excluding loop/sr/zram) instead of major numbers, or document "set `disk_devices` for virtio VMs" (current state, see the comment in `vars/main.yml`).

### 3.4 GRUB hold with a glob

- Where: `tasks/09_1_config_system.yml` "Run command to mark selected APT packages as hold" with `packages_to_mark_hold` (`grub-*`, `grub2`, `grub2-common`) from `vars/main.yml`, `ignore_errors: true`.
- What: `apt-mark hold` may not expand `grub-*` and `grub2` does not exist in Debian. Errors are ignored, so it is unclear if anything is actually held.
- To check: `apt-mark showhold` on an installed system. Then either list the real package names (`grub-common`, `grub-pc`, `grub-efi-amd64`, ...) with `ansible.builtin.dpkg_selections`, or use an apt preferences pin (`Pin-Priority: -1`) to prevent installation entirely.

### 3.5 Remaining ansible-lint warnings

- Cosmetic only: line length (> 160), comma alignment in a few loop lists, two `when: changed` tasks (`18_5` update-initramfs, `19` ssh restart) that could be handlers (they run on the installed system, so handlers would be safe there).
- Two intentional `risky-shell-pipe` cases (`01_basic_checks.yml` by-path lookup with `| head -n1`, `15_unmount_chroot.yml` best-effort unmount): `pipefail` would break them; annotate with `noqa` if the warnings bother.

## 4. Fixes to port to `../ansible_deb_btrfs-on-root` (separate session)

Verified against the btrfs code on 2026-11-04. Commit hashes refer to this repository.

### Bugs present in the btrfs role

- [ ] **Step tags don't work** (`tasks/main.yml`): includes tagged only `bootstrap` (btrfs a2bae3f), so `--tags create_partitions` etc. run nothing. Port the `always` + `when: ansible_run_tags | intersect(<role>_tags)` gating with `apply: tags: [bootstrap]` and a tag list var (`246ea21`). Its CLAUDE.md documents step tags that currently don't work.
- [ ] **Unencrypted swap fstab entries are never written** (`tasks/15_config_swap.yml` lines 19, 92): `echo ... >> /etc/fstab` via `ansible.builtin.command`. Port the `12_6-config_swap.yml` rewrite (`825753f`): `ansible.posix.mount` (path `none`, fstype `swap`), `community.general.crypttab` for `crypt_swap` (the current `echo >> /etc/crypttab` duplicates entries on reruns), drop `apt install` via `command`, `swap_device`/`swap_dev_name` vars.
- [ ] **Single-disk unencrypted LVM** (`tasks/22_config_LVM.yml` line 15): `pvs: "{{ disk_by_id }}-part..."` renders a list. Use `disk_by_id[0]` / an `lvm_device` var.
- [ ] **`no_log` set as a fact** (`tasks/01_basic_checks.yml` line 148): `no_log` is inside the `set_fact` args with a broken Jinja string. Move it to task level.
- [ ] **Passphrase handling** (`01_basic_checks.yml`): passphrase prompt with `echo: true` (line 141); `passphrase: "none"` default (line 177) means LUKS silently gets "none" when no passphrase is given and the prompt is disabled. Port: prompt hidden + confirmation, prompt/validation tagged `always`, fail if encryption is enabled without a passphrase of 8+ characters.
- [ ] **Empty LUKS list** (`tasks/04_clear_partition_tables.yml` line 34): `stdout | split('\n')` gives `['']` without LUKS containers. Use `stdout_lines | select | list`.
- [ ] **sshd**: regex patching of `sshd_config` (`26_final_setup.yml` line 62) and the `sshd` alias (line 70, `handlers/main.yml`). Port the drop-in `/etc/ssh/sshd_config.d/50-*.conf` template gated by `update_sshd_settings` and use the `ssh` unit (`1c7f0e6`, `b9b0737`).
- [ ] **PEP 668 hack** (`18_first_boot_prep.yml` lines 75-85): replace pip + deleting `EXTERNALLY-MANAGED` with the apt package `python3-pexpect` (`b9b0737`).

### Improvements worth porting

- [ ] `templates/hosts.j2`: use the first static address from the network config, fall back to `default_ipv4` (`b9b0737`, uses `if/else` because `ternary` evaluates both branches). Adapt to the btrfs role's `ipv4.iface`/`ipv4.bridge` structure.
- [ ] `tasks/01_test_virtualbox.yml`: drop the Archlinux branches (`b9b0737`).
- [ ] `meta/main.yml`: Debian trixie, `min_ansible_version: "2.18"`, list the required collections (`b9b0737`).
- [ ] Swap on 3+ disks: raid10 instead of raid5 (upstream #10/#11). Only relevant once multi-disk is supported.
- [ ] Cleanup like `1b276b6`: commented-out code in `13_config_esp_filesystem.yml`, `14_install_grub.yml`, `18_first_boot_prep.yml`, `26_final_setup.yml`; 2 remaining error messages referencing `zfs_on_root.yml`; check for unused variables (usage grep, see this repo's history).
- [ ] Docs: playbook examples must not set `ansible_port` via `--extra-vars` (overrides the chroot port 8922); add the handler gotcha (handlers run with play vars, i.e. against the live CD in the chroot phase) to its CLAUDE.md.

### Latent (only once multi-disk support is added)

- [ ] `11_config_boot_filesystem.yml` / `13_config_esp_filesystem.yml` line 55: `mdadm --examine --scan >> mdadm.conf` via `command` (no redirect) with a `creates` that always skips. Port the `mdadm --detail --scan` + `blockinfile` approach (`825753f`). Currently unreachable because `01_basic_checks.yml` rejects more than one disk.

### Already fine in the btrfs role

- `interfaces.j2` has no top-level `dns-*` options; efivars mount is gated on UEFI mode; empty prompt input is handled; LVM crypttab without `initramfs`; bare facts already converted.
