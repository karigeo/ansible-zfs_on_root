# Computer Configuration Settings

[Back to README.md](../README.md)

## UEFI or Legacy BIOS

Does not matter if UEFI or Legacy BIOS is used. When available UEFI will be used, if not available it will automatically fallback to BIOS.  You should be easily able to move between these options.

## Default Domain Name

The default domain name to assign to computers can be defined here.  This value can be overridden per host in the inventory file as needed.

```yaml
# Default domain hosts will use if not defined in inventory file
domain_name: "localdomain"
```

## rEFInd Boot Menu Timeout

By default rEFInd boot menu will wait 20 seconds for you take make a section.  This is a bit on the long side for most configurations.  This value will override this configuration:

```yaml
# rEFInd Boot Menu Timeout by default is 20 seconds.
refind_boot_menu_timeout: "10"
```

## Define Locale and Timezone

Set your locale and timezone information.

```yaml
# Define the local pre-fix to enable in /etc/locale.gen
locale_prefix: "en_US"

# Define the timezone to be placed in /etc/timezone
timezone_value: "America/New_York"
```

## Disable IPv6 Networking

By default IPv6 networking will be disabled.  If you have a need for it, you can set `ipv6.disable: false`. You can also customize which settings are applied and how they are applied as well.

```yaml
# Disable IPv6 if you do not use it.  The "disable_settings" will be applied to
# "conf_file"
ipv6:
  disable: true
  conf_file: "/etc/sysctl.d/99-sysctl.conf"
  disable_settings:
    - "net.ipv6.conf.all.disable_ipv6 = 1"
    - "net.ipv6.conf.default.disable_ipv6 = 1"
    - "net.ipv6.conf.lo.disable_ipv6 = 1"
  apply_cmd: "sysctl -p"
```

## Additional Installed Packages

These are the packages to be be applied to the towards the end of the build process to be included as part of the base system installation.

```yaml
# Define additional packages to install once the build has completed.
additional_install_packages:
  - man
  - udisks2
  - pciutils
  - net-tools
  - ethtool
  - fonts-ubuntu-console
  - htop
  - pollinate
  - fwupd
  - needrestart
  - unattended-upgrades
  - lz4
```

[Back to README.md](../README.md)
