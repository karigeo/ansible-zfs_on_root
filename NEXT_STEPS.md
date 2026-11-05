# Next Steps

Status 2026-11-05: the whole test matrix (section 2) ran on a Proxmox VM with the scripts in `tests/vm/` and passes after 15 fix commits (`121d4b7`..`91706d4` on `dev-deb13`, not pushed). Per-case logs and check outputs are local in `~/.config/claude-zfs-test/logs/`.

## 1. Own playbook and inventory

The test runs use their own playbook/inventory (`tests/vm/`). Your local files still need:

- [ ] Local `playbook.yml` (gitignored): fix the role path (`/Users/simon/Ansible/ansible-zfs_on_root` → `/Users/simon/Ansible/homelab/roles/ansible-zfs_on_root` or the role name) and add `tags: [never, bootstrap]` to the role (optional, the role is inert without its tags anyway).
- [ ] Runs now need `--tags bootstrap` (or a step tag, see README).
- [ ] Local `inventory.yml` (gitignored): convert `ipv4.iface` / `ipv4.bridge` to the current `ipv4.interfaces` / `ipv4.bridges` lists (see `defaults/main.yml`). `public_key_for_dropbear` must be a list of keys, not a path.
- [ ] With `remoteaccess_ip_config: "dhcp"` ZFSBootMenu got a different address than the DHCP reservation in the tests (10.11.30.17 instead of .33); use `"static"` if dropbear must be at a known address.

## 2. Test matrix: results

Proxmox VM (q35, 15 GB disks), Debian Live 13.7.0 standard (kernel 6.12.107), installed kernel 6.12.115. Run with `tests/vm/bin/runcase` (see `tests/vm/README.md`), checks with `tests/vm/checks.sh`.

| # | Disks | Firmware | Encryption | Swap / LVM | Result | Fixes found |
|---|-------|----------|------------|------------|--------|-------------|
| 1 | 1 (scsi) | UEFI (OVMF) | `luks` | swap + LVM | pass | `121d4b7` live kernel headers, `e70f120` gsettings, `b968c2c` rEFInd default, `e2dc18b` step tags, `1747de5` unlock-luks |
| 2 | 1 (scsi) | UEFI | `native` | swap + LVM | pass | `f5054da` native key initramfs hook |
| 3 | 1 (virtio, no serial → by-path) | UEFI | `none` | swap + LVM | pass | `cda8d09` thin-provisioning-tools |
| 4 | 2 | UEFI | `luks` | swap + LVM | pass | `d25bfd5` degraded md arrays, `1527840` crypttab nofail |
| 5 | 3 | UEFI | `luks` | swap + LVM | pass | `f876186` rEFInd NVRAM (ESP corruption), `9500626` mdadm spares, `0cd9930` changed reports |
| 6 | 4 | UEFI | `none` | swap | pass | – |
| 7 | 1 | legacy BIOS (SeaBIOS) | `luks` | swap | pass | `57e66c0` stacked ESP mounts/mvrefind, `91706d4` syslinux default image |
| 8 | 1 | UEFI | `none` | swap + LVM | pass | (`e2dc18b`) |
| 9 | 4 | UEFI | `none`, raidz2 | swap | pass | – |

### Checks (all cases unless noted)

- [x] One passphrase prompt (ZBM), the Debian initramfs unlocks with the embedded keyfile (luks: `cryptroot/keyfiles/<mapper>.key`, native: `etc/zfs/rpool.key`), initrd 0600. luks: no `pve.key` in the initramfs.
- [x] Dropbear at boot (cases 1, 2, 4, 5, 7): luks with the new `unlock-luks`, native with `zbm`; the system boots afterwards.
- [x] Native: all datasets share encryption root `rpool`, keys available, `org.zfsbootmenu:keysource` set.
- [x] Pools: single, mirror, raidz1, mirrored vdev pairs (`mirror-0` + `mirror-1`), raidz2 on 4 disks.
- [x] mdadm: ESP raid1 (metadata 1.0), swap raid1/raid10, LVM raid1/raid5, `ANSIBLE MANAGED ARRAYS` block, one `rEFInd <disk-id>` UEFI entry per disk.
- [x] Disk removed (case 4): boots from the second disk, pool DEGRADED, md arrays started degraded after 30 s (after `d25bfd5`), no failed units.
- [x] Swap (encrypted and plain, single and md), fstab/crypttab without duplicates; LVM thin pool `pve/data` active after boot.
- [x] `ifup --no-act -a` clean, hosts/resolv.conf, sshd drop-in, pexpect + `EXTERNALLY-MANAGED`, no dropbear service, `@base_install` + apt snapshots.
- [x] `apt-mark showhold` lists the grub packages (the `grub-*` glob works, see 3.4).
- [x] Step tags (case 8): untagged run does nothing; `install-zfs-packages`, `clear_partition_tables_from_devices`, `create_partitions`, `create_pools` one after another run only their step + checks.
- [x] Rerun on the installed system: phase-3 tags (`config_lvm`, `install_dropbear`) work, `changed=0` for `config_lvm` (after `0cd9930`).
- [x] Environment checks (`00_check_environment.yml`, 2026-11-05, case 8): full `--tags bootstrap` passes all four checks. Refused with a clear message and no changes: `config_swap` on a fresh live CD (no root dataset at `/mnt`), `create_partitions` with a target partition mounted at `/media/t`, `config_swap` with an unchrooted sshd on 8922, `localization` on the live CD; on the installed system `clear_partition_tables_from_devices` (no `boot=live`; with `require_live_cd=false`: target disk in use), `unmount_chroot`, `config_swap` (partition table and ZBM image unchanged). `config_lvm` on the installed system still runs, `changed=0`. Port 8922 stays: it is transport only, the checks provide the safety.

## 3. Noticed but left unchanged (possible later work)

Found during the review, deliberately not changed because they alter boot behaviour or need a decision. Verify on a VM before changing.

### 3.1 rEFInd never uses `refind_linux.conf`

- Where: `tasks/12_3-install_refind.yml` (template `refind_linux.conf.j2` copied to `{{ zfs_boot_menu_path }}`, `dont_scan_dirs` set from `refind_no_scan_dirs` in `defaults/main.yml`, custom `menuentry "ZFSBootMenu"`).
- What: `refind_no_scan_dirs` excludes the ZBM directory (`EFI/zfsbootmenu`), so rEFInd does not auto-detect the ZBM kernel there, and `refind_linux.conf` (which only applies to auto-detected kernels) is never read. The custom menu entry has `loader` and `initrd` but no `options` line, so ZBM boots without the intended command line: `zbm.prefer=<pool> zbm.import_policy=hostid zbm.set_hostid zbm.timeout=20 ro loglevel=0`. ZBM falls back to its defaults (e.g. the pool's `bootfs`, timeout 10 s). It works, but not as configured.
- Options:
  1. Add `options "zbm.prefer=... ro loglevel=0"` to the custom menu entry and delete `refind_linux.conf.j2` + its task (one source of truth). Decide on `zbm.timeout` (20 s may be too long), and whether `zbm.import_policy=hostid zbm.set_hostid` are wanted (`spl_hostid` is already set per boot environment via `org.zfsbootmenu:commandline`).
  2. Drop the custom menu entry and `dont_scan_dirs`, and let rEFInd auto-detect ZBM with `refind_linux.conf` (loses the custom icon/title).
  3. Keep as is and only delete the unused template.
- Related: the ZBM config (`templates/zfsbootmenu_config.yaml.j2`) has `Kernel: CommandLine: zbm.prefer=<pool> ro loglevel=0`, which only applies to EFI bundles (disabled, `EFI: Enabled: false`). The syslinux entries generated by `syslinux-update.sh` have no `APPEND` line either (`ZBM_KCL_ARGS=""`), so legacy BIOS boots ZBM with its defaults as well. Confirmed in the VM tests: ZBM shows its default countdown (10 s) on both paths.

### 3.2 `rd.break` on the dropbear network command line

- Where: `tasks/18_enable_dropbear.yml`, both "Create file /etc/cmdline.d/dracut-network.conf" tasks (DHCP and static) end with `rd.break`. The line goes into the ZBM image (`install_optional_items` in `dracut_dropbear.conf.j2`).
- What: `rd.break` tells dracut to drop to a shell at the end of the initramfs. It comes from upstream (Ubuntu era) and was kept through `e5d589b` / `06cca0c`. In the ZBM image it may be what makes the dropbear session land in the "ZFSBootMenu initramfs shell" (banner: enter `zbm`), or it may be a leftover with no effect.
- To check: boot with and without `rd.break` (edit `/etc/cmdline.d/dracut-network.conf`, `generate-zbm`) and compare console and dropbear behaviour. Remove it if ZBM and dropbear work the same without it; otherwise document why it is needed.

### 3.3 Automatic disk detection skips virtio disks

- Where: `lsblk_device_types: "8,179,259"` in `vars/main.yml`, used by `lsblk_device_command` / `lsblk_device_detail_command` for the disk prompt in `tasks/01_basic_checks.yml` (only when `disk_devices` is not set).
- What: virtio-blk (`vda`) has a dynamically assigned major number (often 252-254), so it is neither listed nor suggested. Device-mapper also uses a dynamic major, so simply adding 252/253 could list dm devices.
- Options: select by `lsblk -ndo name,type,ro` with `TYPE == "disk"` (and excluding loop/sr/zram) instead of major numbers, or document "set `disk_devices` for virtio VMs" (current state, see the comment in `vars/main.yml`).

### 3.4 GRUB hold with a glob (checked, works)

- `apt-mark showhold` on the installed test systems lists all `grub*` packages (`grub-common`, `grub-efi-amd64`, `grub-pc`, `grub2`, ...): `apt-mark hold` expands the glob against the package names. Nothing to change; `ignore_errors: true` could be dropped.

### 3.5 Remaining ansible-lint warnings

- Cosmetic only: line length (> 160), comma alignment in a few loop lists, two `when: changed` tasks (`18_5` update-initramfs, `19` ssh restart) that could be handlers (they run on the installed system, so handlers would be safe there).
- Two intentional `risky-shell-pipe` cases (`01_basic_checks.yml` by-path lookup with `| head -n1`, `15_unmount_chroot.yml` best-effort unmount): `pipefail` would break them; annotate with `noqa` if the warnings bother.

### 3.6 No zstd on the target

- `update-initramfs` warns `No zstd in /usr/bin:/sbin:/bin, using gzip`: Debian's default `COMPRESS=zstd`, but `zstd` is not installed on the new system. Adding `zstd` to `packages_standard` gives smaller/faster initramfs images.

### 3.7 Test harness notes

- The controller (Mac) must stay awake for the whole run; `tests/vm/bin/play` uses `caffeinate -i -s`. Without it the run stalls whenever macOS sleeps (looks like a hanging SSH connection).
- Under SeaBIOS the live system waits at shutdown for "remove the live-medium and press ENTER" (live-boot). `tests/vm/iso/build.sh` now passes `noeject`; the ISO uploaded for these tests was built before that.

## 4. Fixes to port to `../ansible_deb_btrfs-on-root` (separate session)

Verified against the btrfs code on 2026-11-04. Commit hashes refer to this repository.

### Bugs present in the btrfs role

- [ ] **Step tags don't work** (`tasks/main.yml`): includes tagged only `bootstrap` (btrfs a2bae3f), so `--tags create_partitions` etc. run nothing. Port the `always` + `when: ansible_run_tags | intersect(<role>_tags)` gating with `apply: tags: [bootstrap]` and a tag list var (`246ea21`). Its CLAUDE.md documents step tags that currently don't work.
- [ ] **Environment checks** (port together with the step tags, which would otherwise open the same hole): once step tags work, `--tags <wipe/partition step>` against an installed system runs on port 22 and wipes its disks. Port `tasks/00_check_environment.yml`, `files/target_disk_usage.sh`, `require_live_cd` and the four tag groups in `vars/main.yml`/`tasks/main.yml`. Adapt the root checks: `/` is a btrfs subvolume of the root partition (`findmnt` SOURCE `/dev/...[/@]`), not a ZFS dataset.
- [ ] **Unencrypted swap fstab entries are never written** (`tasks/15_config_swap.yml` lines 19, 92): `echo ... >> /etc/fstab` via `ansible.builtin.command`. Port the `12_6-config_swap.yml` rewrite (`825753f`): `ansible.posix.mount` (path `none`, fstype `swap`), `community.general.crypttab` for `crypt_swap` (the current `echo >> /etc/crypttab` duplicates entries on reruns), drop `apt install` via `command`, `swap_device`/`swap_dev_name` vars.
- [ ] **Single-disk unencrypted LVM** (`tasks/22_config_LVM.yml` line 15): `pvs: "{{ disk_by_id }}-part..."` renders a list. Use `disk_by_id[0]` / an `lvm_device` var.
- [ ] **`no_log` set as a fact** (`tasks/01_basic_checks.yml` line 148): `no_log` is inside the `set_fact` args with a broken Jinja string. Move it to task level.
- [ ] **Passphrase handling** (`01_basic_checks.yml`): passphrase prompt with `echo: true` (line 141); `passphrase: "none"` default (line 177) means LUKS silently gets "none" when no passphrase is given and the prompt is disabled. Port: prompt hidden + confirmation, prompt/validation tagged `always`, fail if encryption is enabled without a passphrase of 8+ characters.
- [ ] **Empty LUKS list** (`tasks/04_clear_partition_tables.yml` line 34): `stdout | split('\n')` gives `['']` without LUKS containers. Use `stdout_lines | select | list`.
- [ ] **sshd**: regex patching of `sshd_config` (`26_final_setup.yml` line 62) and the `sshd` alias (line 70, `handlers/main.yml`). Port the drop-in `/etc/ssh/sshd_config.d/50-*.conf` template gated by `update_sshd_settings` and use the `ssh` unit (`1c7f0e6`, `b9b0737`).
- [ ] **PEP 668 hack** (`18_first_boot_prep.yml` lines 75-85): replace pip + deleting `EXTERNALLY-MANAGED` with the apt package `python3-pexpect` (`b9b0737`).
- [ ] **LVM thin pool inactive after boot** (`tasks/22_config_LVM.yml` line 225 creates a thin pool): install `thin-provisioning-tools` (`thin_check`), otherwise the pool is not activated at boot without an encrypted LVM container (`cda8d09`).
- [ ] **Useless gsettings task** (`tasks/03_install_btrfs_packages.yml`): runs as root, never affects the live user's GNOME session and fails on non-desktop ISOs; `do_ssh.sh` already disables automount. Remove it (`e70f120`).

### Improvements worth porting

- [ ] `templates/hosts.j2`: use the first static address from the network config, fall back to `default_ipv4` (`b9b0737`, uses `if/else` because `ternary` evaluates both branches). Adapt to the btrfs role's `ipv4.iface`/`ipv4.bridge` structure.
- [ ] `tasks/01_test_virtualbox.yml`: drop the Archlinux branches (`b9b0737`).
- [ ] `meta/main.yml`: Debian trixie, `min_ansible_version: "2.18"`, list the required collections (`b9b0737`).
- [ ] Swap on 3+ disks: raid10 instead of raid5 (upstream #10/#11). Only relevant once multi-disk is supported.
- [ ] Cleanup like `1b276b6`: commented-out code in `13_config_esp_filesystem.yml`, `14_install_grub.yml`, `18_first_boot_prep.yml`, `26_final_setup.yml`; 2 remaining error messages referencing `zfs_on_root.yml`; check for unused variables (usage grep, see this repo's history).
- [ ] Docs: playbook examples must not set `ansible_port` via `--extra-vars` (overrides the chroot port 8922); add the handler gotcha (handlers run with play vars, i.e. against the live CD in the chroot phase) to its CLAUDE.md.

### Latent (only once multi-disk support is added)

- [ ] `11_config_boot_filesystem.yml` / `13_config_esp_filesystem.yml` line 55: `mdadm --examine --scan >> mdadm.conf` via `command` (no redirect) with a `creates` that always skips. Port the `mdadm --detail --scan` + `blockinfile` approach (`825753f`). Currently unreachable because `01_basic_checks.yml` rejects more than one disk. Strip `spares=N` from the scan output (`9500626`) and don't combine `creates` with `changed_when: rc == 0` (`0cd9930`).

### Already fine in the btrfs role

- `interfaces.j2` has no top-level `dns-*` options; efivars mount is gated on UEFI mode; empty prompt input is handled; LVM crypttab without `initramfs`; bare facts already converted.
