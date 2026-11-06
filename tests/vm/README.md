# VM Tests on Proxmox

Scripts to run the test matrix of `NEXT_STEPS.md` unattended on one Proxmox VM: each case
recreates the VM disks, boots a prepared Debian Live ISO, runs the role, answers the
passphrase prompts (console and dropbear) and leaves a log for the checks.

The scripts run on the Ansible controller (tested on macOS) and use the Proxmox API with
a token that only has access to the test VM. Nothing here needs root on the Proxmox host.

## Layout

| Path | Purpose |
|------|---------|
| `bin/runcase` | Run one case: fresh disks, wait for the live system, playbook, `autounlock` |
| `bin/play` | `ansible-playbook` with the test inventory and a case file (keeps the Mac awake) |
| `bin/vmprep` | Stop the VM, delete all disks, create fresh ones, set firmware/boot order, start |
| `bin/autounlock` | 1st reboot: types the passphrase on the console; 2nd reboot: `unlock-luks` / `zbm` over dropbear |
| `bin/pve` | Proxmox API helper (curl, token from `pve.env`, never printed) |
| `bin/pvecon` | Console screenshots and keyboard input (vncproxy + vncwebsocket, vncdotool) |
| `bin/zbm-remote` | Run `zbm` over dropbear with a pty and enter a native encryption passphrase |
| `bin/vmssh`, `bin/waitssh` | SSH to the VM with the test key, wait for the live/installed system |
| `bin/tagrun` | Case 8 helper (step tags) |
| `checks.sh` | Post-install checks, run as root on the installed system |
| `cases/caseN.yml` | Extra vars per case |
| `iso/` | Build of the test live ISO (`build.sh`, live-config hook, prep script) |

Local settings and secrets stay outside the repository in `$ZFS_TEST_DIR`
(default `~/.config/claude-zfs-test`, mode 0700):

| File | Content |
|------|---------|
| `pve.env` (0600) | `PVE_URL`, `PVE_NODE`, `PVE_VMID`, `PVE_DISK_STORE`, `PVE_ISO_STORE`, `PVE_TOKEN_ID`, `PVE_TOKEN_SECRET` |
| `pve-root-ca.pem` | `/etc/pve/pve-root-ca.pem` of the Proxmox host |
| `vm.env` | Test VM network, hostname, passphrase, ISO volume (see `vm.env.example`) |
| `inventory.yml` | Test inventory (see `inventory.yml.example`) |
| `id_ed25519`, `id_ed25519.pub` | Test SSH key (live `ansible` user, dropbear) |
| `venv/` | Python venv with `vncdotool websockets pexpect` |
| `iso/`, `logs/` | ISO build directory, playbook logs, check outputs and screenshots |

## One-time Setup

### Proxmox (as root)

Create the test VM yourself (q35, 4+ GB RAM, NIC with a fixed MAC, protection off, not in HA),
then a user and token limited to it:

```bash
VMID=<test VM id>; DISK_STORE=local-lvm; ISO_STORE=local
pveum role add ZfsTestVM -privs "VM.Audit,VM.PowerMgmt,VM.Console,VM.Config.Disk,VM.Config.CDROM,VM.Config.Options,VM.Config.HWType"
pveum role add ZfsTestStorageRead -privs "Datastore.Audit"
pveum user add zfstest@pve -comment "ZFS role VM tests"
pveum acl modify /vms/$VMID -users zfstest@pve -roles ZfsTestVM
pveum acl modify /storage/$DISK_STORE -users zfstest@pve -roles PVEDatastoreUser
pveum acl modify /storage/$ISO_STORE -users zfstest@pve -roles ZfsTestStorageRead
pveum user token add zfstest@pve tests -privsep 0 -expire $(date -d '+30 days' +%s)
```

The token can start/stop and reconfigure this VM, use its console and allocate disks on
`DISK_STORE`; nothing else. Keep about 4 x 15 GB free on `DISK_STORE` for the 4-disk cases.

### Controller

```bash
mkdir -m 700 ~/.config/claude-zfs-test && cd ~/.config/claude-zfs-test
# pve.env (chmod 600), pve-root-ca.pem, vm.env and inventory.yml from the examples
ssh-keygen -t ed25519 -N '' -C zfs-test -f id_ed25519
python3 -m venv venv && venv/bin/pip install vncdotool websockets pexpect
brew install xorriso
```

### Live ISO

```bash
mkdir -p iso/download iso/orig && cd iso/download
B=https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid
curl -fLO $B/SHA512SUMS && curl -fLO $B/debian-live-<version>-amd64-standard.iso
grep standard.iso$ SHA512SUMS | shasum -a 512 -c -
cd .. && bsdtar -xf download/debian-live-*-standard.iso -C orig boot/grub/grub.cfg isolinux
<repo>/tests/vm/iso/build.sh debian-live-<version>-amd64-standard.iso zfs-test-live.iso
```

Upload the ISO to `ISO_STORE` and set `VM_ISO` in `vm.env`. The ISO boots without a menu,
sets the static IP of `vm.env` (DHCP reservations were not reliable), runs `files/do_ssh.sh`
unchanged (non-interactive branch) and installs the test key for the `ansible` user.
`/run/zfs-test-ready` marks the end of the preparation.

## Running the Cases

```bash
bin/runcase 1 1 ovmf scsi luks        # case, disks, ovmf|seabios, scsi|virtio, none|luks|native
tail -f ~/.config/claude-zfs-test/logs/case1.log ~/.config/claude-zfs-test/logs/case1-autounlock.log
bin/vmssh ansible@<vm ip> 'sudo bash -s' < checks.sh
```

| Case | Command |
|------|---------|
| 1 | `runcase 1 1 ovmf scsi luks` |
| 2 | `runcase 2 1 ovmf scsi native` |
| 3 | `runcase 3 1 ovmf virtio none` |
| 4 | `runcase 4 2 ovmf scsi luks` |
| 5 | `runcase 5 3 ovmf scsi luks` |
| 6 | `runcase 6 4 ovmf scsi none` |
| 7 | `runcase 7 1 seabios scsi luks` |
| 8 | `vmprep 1 ovmf scsi`, `waitssh live`, then `tagrun <name> [--tags ...]` |
| 9 | `runcase 9 4 ovmf scsi none` (raidz2) |
| 10 | Reinstall: `runcase 10 2 ovmf scsi none`; on the installed system `efibootmgr -n <DVD entry>` and reboot (live CD once, EFI vars and disks stay), `waitssh live`, `play 10 --tags bootstrap --skip-tags confirm_defaults` |

Disk failure test (multi-disk): power off, `pve PUT /nodes/{node}/qemu/{vmid}/config delete=scsi0 'boot=order=scsi1;ide2'`, start.

## Notes

* The controller must not sleep during a run: `play` wraps `ansible-playbook` in
  `caffeinate -i -s` (macOS). A sleeping Mac looks like a hanging SSH connection.
* ZFSBootMenu requests its own DHCP lease for dropbear, `autounlock` scans `VM_SCAN_NET` for port 222.
* Changing the boot order of a running VM needs a stop/start; a reset keeps the old order.
