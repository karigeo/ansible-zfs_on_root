# Disk Encryption Settings

[Back to README.md](../README.md)

## Encryption Types

The encryption type is selected with `disk_encryption_type` in `defaults/main.yml`:

```yaml
# "native" for ZFS native encryption
# "luks" for LUKS encryption
# "none" for no encryption
disk_encryption_type: luks
```

| Type     | Root pool                                                      | Swap                               | LVM partition (if enabled)   |
|----------|----------------------------------------------------------------|------------------------------------|------------------------------|
| `luks`   | ZFS pool on LUKS containers (one per disk)                     | plain dm-crypt, random key per boot | LUKS container with keyfile |
| `native` | ZFS native encryption (aes-256-gcm), one encryption root: the pool | plain dm-crypt, random key per boot | LUKS container with keyfile |
| `none`   | unencrypted                                                    | unencrypted                        | unencrypted                  |

The same passphrase is used for the root pool (LUKS or native) and the LUKS container of the LVM partition.

### LUKS

* ZFSBootMenu unlocks the LUKS containers of the root partitions with the [zbm-luks-unlock](https://github.com/agorgl/zbm-luks-unlock) hooks (passphrase prompt, also available via [Dropbear](dropbear-settings.md)).
* The booted system unlocks the containers again from `/etc/crypttab` with a random keyfile (`/etc/cryptsetup-keys.d/<root_pool_name>.key`) embedded in the initramfs, so the passphrase is only entered once.
* LUKS does not affect ZFS features: replication (`zfs send`/`recv`) of guest volumes works as usual. This is why LUKS is the default for Proxmox VE hosts.

### ZFS Native Encryption

* Encryption is set when the pool is created, on the pool's root dataset. All datasets (`ROOT`, the OS datasets, `home`, `data`, ...) inherit it and share **one encryption root**, so the pool is unlocked once.
* The passphrase is stored in a keyfile (`/etc/zfs/<root_pool_name>.key`, `keylocation=file://...`) inside the encrypted root dataset:
  * ZFSBootMenu asks for the passphrase, then reads the keyfile via `org.zfsbootmenu:keysource`.
  * The keyfile is embedded in the initramfs (initramfs-tools hook `zfs-native-key`, `UMASK=0077`), so the booted system unlocks the pool without a second prompt.
* Consequences of one pool-level encryption root:
  * Unencrypted datasets cannot be created in this pool. ZFS does not allow unencrypted children of an encrypted dataset. Raw received datasets (`zfs send -w`) keep their own encryption root.
  * Encryption cannot be turned off later; the passphrase can be changed with `zfs change-key` (update the keyfile and regenerate the initramfs afterwards).
* ZFS native encryption encrypts data and _most_ metadata. It does not encrypt dataset names, snapshot names or properties.
* Proxmox VE has limitations with natively encrypted datasets (e.g. storage replication and migration of guests). Prefer `luks` if you need these features.

---

## How to Supply the Passphrase

The passphrase (at least 8 characters) can be specified with the Ansible command line parameter `--extra-vars`:

```bash
ansible-playbook -i inventory.yml ./playbook.yml --tags bootstrap --extra-vars='{passphrase: "mySecr3tPa55"}'
```

If no passphrase is provided and `prompt_for_zfs_passphrase` is `true`, you will be prompted for it (hidden input, entered twice). If it is `false` and no passphrase is provided, the playbook stops with an error.

```yaml
# Prompt for the encryption passphrase (LUKS or native) if none is provided.
prompt_for_zfs_passphrase: true
```

The passphrase is not needed with `disk_encryption_type: none`.

[Back to README.md](../README.md)
