# Computer Configuration Settings

[Back to README.md](../README.md)

## UEFI or Legacy BIOS

Both are supported. The mode is taken from the live CD: UEFI if it was booted in UEFI mode (`/sys/firmware/efi` exists), otherwise legacy BIOS. rEFInd (UEFI) and syslinux (legacy BIOS, boot code in the protective MBR of every disk) are both installed on the ESP in either mode.

* The UEFI boot entries are only created when installing in UEFI mode. After installing in legacy BIOS mode, switching to UEFI needs a boot entry for `\EFI\refind\refind_x64.efi` (see [UEFI BIOS Bugs / Glitches / Issues](uefi-bugs-issues.md)). Multi-disk installs also get `startup.nsh` on the ESP, which the UEFI shell runs to start rEFInd.
* Only the boot mode used for the installation is covered by the VM tests.

## Default Domain Name

The default domain name to assign to computers can be defined here. This value can be overridden per host in the inventory file as needed.

```yaml
# Default domain hosts will use if not defined in inventory file
domain_name: "localdomain"
```

## rEFInd Boot Menu

```yaml
# rEFInd boot menu timeout in seconds (rEFInd default is 20)
refind_boot_menu_timeout: "5"

# Specify rEFInd display resolution to use (width height)
# Default is "0 0", which sets system default resolution
# "max" tries to set the maximum possible resolution
refind_resolution: "0 0"

# Enable a rEFInd theme, cloned from refind_theme_repo into themes/<refind_theme_name>.
refind_theming: true
refind_theme_name: refind-ambience
refind_theme_repo: https://github.com/karigeo/refind-ambience
```

The theme repository is cloned from its `master` branch. It must contain a `theme.conf` (included from `refind.conf`) and the icon `icons/os_proxmox.png`, which is used for the ZFSBootMenu entry. With `refind_theming: false` the default rEFInd look is used.

The ZFSBootMenu entry is the rEFInd default (`default_selection`). The ZFSBootMenu directory is not scanned by rEFInd (`refind_no_scan_dirs`), so it shows up only once.

## Locale, Timezone and Keyboard

```yaml
# Default locale (generated and set in /etc/default/locale)
default_locale: "en_US.UTF-8"
# Further locales that should be generated and present
locales_list:
  - "de_DE.UTF-8"

# Variables written to /etc/default/locale
apply_locale_settings:
  LANG: "{{ default_locale }}"

# Timezone of the new system
timezone_area: "Europe"
timezone_city: "Berlin"
localization_timezone: "{{ timezone_area }}/{{ timezone_city }}"

# Keyboard configuration written to /etc/default/keyboard
keyboard_model: "pc105"
keyboard_layout: "us"
keyboard_variant: ""
keyboard_options: ""
keyboard_backspace: "guess"
```

## Network

The network configuration of the new system is written to `/etc/network/interfaces` (physical interfaces and Linux bridges, as Proxmox VE expects them) and `/etc/resolv.conf`:

```yaml
# address_type can be "manual", "static" or "dhcp"; network_address uses CIDR notation.
ipv4:
  interfaces:  # List of physical interfaces
    - name: eno1
      address_type: manual
  bridges:  # List of bridges, each with their bridge-ports (reference to interface.name)
    - name: vmbr0
      address_type: static
      network_address: "192.168.100.10/24"
      gateway: 192.168.100.1
      bridge_ports:
        - eno1
      vlan_aware: true
      bridge_vids: "2-4094"
  dns_nameserver: 192.168.100.1
  dns_search_domain: my.do.main   # "none" to omit the search line
```

* `address_type` is `manual` (no address, e.g. a bridge port), `static` (needs `network_address` in CIDR notation and `gateway`) or `dhcp`.
* `ipv4.interfaces` must list at least one interface. The first one is also the default Dropbear device.
* Ansible reconnects to the same address after the first reboot, so the new system must come up with the address the live CD had (static address or DHCP reservation).
* `/etc/hosts` gets the first static address (bridges first), otherwise the live system's address.
* Use `bridges: []` for a plain host without bridges.

## Disable IPv6 Networking

By default IPv6 networking will be disabled (in `final_setup`, tag `disable_ipv6`). If you need it, set `ipv6.disable: false`. The `disable_settings` lines are added to `conf_file` and applied with `apply_cmd <conf_file>`.

```yaml
ipv6:
  disable: true
  conf_file: "/etc/sysctl.d/99-sysctl.conf"
  disable_settings:
    - "net.ipv6.conf.all.disable_ipv6 = 1"
    - "net.ipv6.conf.default.disable_ipv6 = 1"
    - "net.ipv6.conf.lo.disable_ipv6 = 1"
  apply_cmd: "sysctl -p"
```

## Installed Packages

A minimal server package set (`packages_standard` in `vars/main.yml`, with recommends) is installed in `final_setup`. Additional packages (installed without recommends) can be defined in `defaults/main.yml`:

```yaml
# Additional packages to install once the build has completed
# (on top of packages_standard in vars/main.yml)
additional_install_packages:
  - udisks2
  - net-tools
  - fwupd
  - pollinate
```

[Back to README.md](../README.md)
