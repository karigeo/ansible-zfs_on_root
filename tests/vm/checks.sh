#!/bin/bash
# Post-install checks from NEXT_STEPS.md, run as root on the installed system.
# Usage: bin/vmssh ansible@<vm> 'sudo bash -s' < checks.sh
sec() { printf '\n===== %s\n' "$*"; }
sec uname/hostname; uname -r; hostname -f
sec zpool status; zpool status
sec zfs list; zfs list -o name,used,mountpoint,canmount,encryption
sec encryption; zfs get -H -o name,property,value encryption,encryptionroot,keystatus,keylocation -r rpool | grep -v -- '-$' | head -40
sec 'zbm properties'; zfs get -H -o name,property,value -s local all rpool rpool/ROOT rpool/ROOT/* | grep -E 'org.zfsbootmenu|bootfs|keysource'; zpool get -H bootfs rpool
sec initramfs keys; lsinitramfs /boot/initrd.img-"$(uname -r)" | grep -E 'rpool.key|cryptsetup-keys|pve.key|zfs/.*key' ; ls -l /boot/initrd.img-*
sec mdstat; cat /proc/mdstat
sec mdadm.conf; sed -n '/BEGIN ANSIBLE MANAGED ARRAYS/,/END ANSIBLE MANAGED ARRAYS/p' /etc/mdadm/mdadm.conf
sec swap; swapon --show
sec fstab; cat /etc/fstab
sec crypttab; cat /etc/crypttab
sec lvm; pvs; vgs; lvs
sec lsblk; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
sec efibootmgr; if [ -d /sys/firmware/efi ]; then efibootmgr -v | grep -v '^ *dp:\|^ *data:'; else echo "legacy BIOS"; fi
sec 'refind.conf'; f=/boot/efi/EFI/refind/refind.conf; [ -f "$f" ] && grep -nE '^(timeout|default_selection|dont_scan_dirs|scanfor|include)' "$f"
sec ifup no-act; ifup --no-act -a 2>&1 | head -20
sec interfaces; cat /etc/network/interfaces
sec hosts/resolv; cat /etc/hosts /etc/resolv.conf
sec sshd; sshd -T | grep -iE '^(passwordauthentication|permitrootlogin|pubkeyauthentication|usepam) '; cat /etc/ssh/sshd_config.d/50-zfs_on_root.conf
sec pexpect; python3 -c 'import pexpect; print("pexpect", pexpect.__version__)'; ls /usr/lib/python3*/EXTERNALLY-MANAGED
sec dropbear service; systemctl status dropbear 2>&1 | head -2; dpkg -l | grep -E 'dropbear' | awk '{print $1, $2, $3}'
sec snapshots; zfs list -t snapshot -o name,creation
sec apt hold; apt-mark showhold
sec 'failed units'; systemctl --failed --no-legend
sec 'boot errors'; journalctl -b -p err --no-pager | tail -20
