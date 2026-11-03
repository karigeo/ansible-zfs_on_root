# Additional Playbook Examples

[Back to README.md](../README.md)

The following examples show overriding values from the command-line. Typically it will be easier to define these in the inventory or host_vars instead.

The `playbook.yml` referenced in the examples below is a simple yaml file used to call the role, which can look like this:

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

The role only runs when `--tags bootstrap` (everything) or one of its step tags is given, see [Alternative Step by Step Installation](../README.md#alternative-step-by-step-installation). The `[never, bootstrap]` tags on the role are optional, they make the intent visible in a site playbook.

---

NOTE: The role configures the live CD's `sshd` to listen on port 22 and on port 8922 (chrooted into the new system, used for the chroot phase). Don't set `ansible_port` with `--extra-vars`, extra vars would override the chroot port.

To provide the encryption passphrase (LUKS or native, see `disk_encryption_type`):

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{passphrase: "mySecr3tPa55"}' -l <remote_host_name>
```

To define specific devices or a sub-set of available devices:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{disk_devices: [sda, sdb]}' -l <remote_host_name>
```

To define an alternate hostname (other than one used for SSH connection):

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{host_name: testlinux}' -l <remote_host_name>
```

To enable some debug or verbose output:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{debug: true}' -l <remote_host_name>

# To enable ansible verbose details as well:
ansible-playbook -vvvv -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{debug: true}' -l <remote_host_name>
```

* `-vvvv` is VERY verbose (and slower). You can start with just `-v` and add more `v` to increase verbosity if needed.

To do multiple of these at the same time:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{disk_devices: [sda, sdb], host_name: testlinux, passphrase: "mySecr3tPa55"}' -l <remote_host_name>
```

If the above is too complicated, no worries. The playbook will show you the detected defaults and let you just type values. It will also show you a summary screen of values for your reference and allow you to abort.

[Back to README.md](../README.md)
