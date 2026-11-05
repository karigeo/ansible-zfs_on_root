# Helper Scripts

[Back to README.md](../README.md)

## do_ssh.sh

Once the Debian Live CD is booted on the target system, a few steps are needed so Ansible can connect to it over the network: create an `ansible` user account with a password, grant it `sudo` without password, install the SSH server and Python, etc. The helper script `files/do_ssh.sh` does all of this:

```bash
wget https://raw.githubusercontent.com/karigeo/ansible-zfs_on_root/main/files/do_ssh.sh

chmod +x do_ssh.sh

./do_ssh.sh
```

* When prompted for the Ansible password, enter and confirm it. This is a temporary password, only needed to push the SSH key to the target machine. It only exists on the live CD: the `ansible` user of the new system has no password, only SSH key authentication is allowed.

### If "do_ssh.sh" is not Available

These are the commands the helper script runs. Enter them at the shell prompt of the live CD:

```bash
sudo useradd -m ansible -s /bin/bash
sudo passwd ansible
echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99_sudo_include_file
sudo visudo -cf /etc/sudoers.d/99_sudo_include_file

sudo apt install --yes openssh-server python3 python3-apt python3-pexpect mdadm
sudo swapoff -a
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Desktop image only: don't automount disks that were used before
gsettings set org.gnome.desktop.media-handling automount false
```

The script also installs `vim`, `htop`, `btop` and `qemu-guest-agent` (and starts the agent), which is optional.

[Back to README.md](../README.md)
