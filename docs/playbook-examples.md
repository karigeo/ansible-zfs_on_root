# Additional Playbook Examples

[Back to README.md](../README.md)

The following examples show overriding values from the command-line. Typically it will be easier to define these in the inventory or host_vars instead.

The examples use the `playbook.yml` from the [README](../README.md#fire-up-the-ansible-playbook). The role only runs when `--tags bootstrap` (everything) or one of its step tags is given, see [Alternative Step by Step Installation](../README.md#alternative-step-by-step-installation).

---

NOTE: The role configures the live CD's `sshd` to listen on port 22 and on port 8922 (chrooted into the new system, used for the chroot phase). Don't set `ansible_port` with `--extra-vars`: extra vars would override the chroot port.

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

Values that are not set (`disk_devices`, `host_name`, `passphrase`) are prompted for, with the detected defaults suggested. Before anything is changed, a summary screen of the settings is shown and you can abort (skip it with `--skip-tags confirm_defaults`).

The passphrase can also be kept in the optional `secrets/main.yml` of the role (not tracked by git) instead of the command line.

[Back to README.md](../README.md)
