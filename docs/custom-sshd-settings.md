# Customized SSHD Settings

[Back to README.md](../README.md)

## Enable SSHD Configuration

`update_sshd_settings` in `defaults/main.yml` enables (`true`) or disables (`false`) applying the SSHD settings below.

## SSHD Configuration Settings

The settings in `apply_sshd_settings` are written as `Key value` lines to the drop-in file `/etc/ssh/sshd_config.d/50-zfs_on_root.conf` (validated with `sshd -t`). Debian's `/etc/ssh/sshd_config` includes `sshd_config.d/*.conf` at the top and the first value found wins, so these settings override the defaults. Any `sshd_config` keyword and value can be used (no `Match` blocks).

```yaml
###############################################################################
# SSH Settings
###############################################################################
update_sshd_settings: true
apply_sshd_settings:
  PasswordAuthentication: "no"
  PermitRootLogin: "prohibit-password"
  PubkeyAuthentication: "yes"
  UsePAM: "yes"
```

Values can be changed and new entries can be added. To deploy changes (the `ssh` service is restarted when the file changes):

```bash
ansible-playbook -i inventory.yml ./playbook.yml -l <remote_host_name> --tags="update_sshd_settings"
```

[Back to README.md](../README.md)
