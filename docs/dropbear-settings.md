# Dropbear Configuration Settings

[Back to README.md](../README.md)

## Dropbear in ZFSBootMenu

This adds a small SSH server ([Dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html), via the [dracut-crypt-ssh](https://github.com/dracut-crypt-ssh/dracut-crypt-ssh) module) to the ZFSBootMenu image. You can connect remotely at boot time to enter the encryption passphrase (LUKS or ZFS native). Once entered, the system continues to boot. Without encryption there is no need to enable this.

* Dropbear only runs inside ZFSBootMenu (port 222). There is no dropbear service on the installed system and no dropbear in its initramfs.
* Dropbear uses the system's OpenSSH host keys (ECDSA, ED25519), so it presents the same host keys as `sshd`.
* Login is key-based only, always as `root`.

### Enable Dropbear

Dropbear is configured in `defaults/main.yml` (task file `18_enable_dropbear.yml`, after the first reboot):

```yaml
enable_dropbear_support: true
apply_dropbear_settings:
  # Physical network device to bring up for remote access
  remoteaccess_device: "{{ ipv4.interfaces[0].name }}"
  # IP configuration for ZFSBootMenu remote access (dracut ip= option):
  # "dhcp", "dhcp6", "on", "any", "auto6", "link6" or "static"
  remoteaccess_ip_config: "dhcp"
  # Remote access static IP address to connect to ZFSBootMenu
  # Only used with "static", not used for dhcp or dhcp6 automatic IP configuration
  remoteaccess_ip: "192.168.100.10"
  # Remote access subnet mask
  # Only used with "static", not used for dhcp or dhcp6 automatic IP configuration
  remoteaccess_netmask: "255.255.255.0"
  # Remote access gateway
  # Only used with "static"
  remoteaccess_gateway: "192.168.100.1"
  # List of public keys (authorized_keys lines) allowed to log in to dropbear.
  # Note that login to dropbear is "root" regardless of the key used.
  public_key_for_dropbear: ["ssh-ed25519 ABCDEFG user@machine"]
```

* `remoteaccess_device` is matched by its MAC address, so the name of the device inside ZFSBootMenu does not matter.
* With `remoteaccess_ip_config: "static"` set `remoteaccess_ip`, `remoteaccess_netmask` and `remoteaccess_gateway`.
* The network configuration is written to `/etc/cmdline.d/dracut-network.conf`. `rd.neednet=1` is not set, so the system still boots without network.

### Dropbear Keys

`public_key_for_dropbear` is a list of public keys. They are written to `/etc/dropbear/authorized_keys`, which is included in the ZFSBootMenu image. After changing that file manually, regenerate the image:

```shell
sudo generate-zbm --debug
```

### Manual Execution or Refresh Settings

To install Dropbear or update its configuration later, run only this step:

```bash
ansible-playbook -i inventory.yml ./playbook.yml -l <remote_host_name> --tags="install_dropbear"
```

### Connecting to Dropbear

When the system boots, connect as `root` on port 222 with one of the configured keys:

```bash
$ ssh -i ~/.ssh/dropbear_ed25519 -p 222 root@<remote_host_name>

Welcome to the ZFSBootMenu initramfs shell. Enter "zfsbootmenu" or "zbm" to start ZFSBootMenu.
zfsbootmenu ~ >
```

* Enter `zbm` to access ZFSBootMenu.
* You are prompted for the passphrase: for LUKS the partitions to unlock are listed first, for ZFS native encryption the prompt names the pool (`Enter passphrase for '<root_pool_name>':`).
* Select what to boot (or roll back to a snapshot). The connection is closed and the system boots. Dropbear does not run once the system has booted.

### Changing the Dropbear Banner Text

The banner is defined in `templates/dracut_banner.txt.j2` and placed at `/etc/zfsbootmenu/dracut.conf.d/banner.txt`. After modifying that file, regenerate the image with `sudo generate-zbm --debug`.

### Dropbear Configuration File

The dracut configuration for Dropbear is defined in `templates/dracut_dropbear.conf.j2` and placed at `/etc/zfsbootmenu/dracut.conf.d/dropbear.conf`. After modifying that file, regenerate the image with `sudo generate-zbm --debug`.

[Back to README.md](../README.md)
