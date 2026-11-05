#!/bin/bash
# Prepares the live system for the ZFS role tests: network, files/do_ssh.sh, test SSH key.
MED=/run/live/medium/zfs-test
exec > >(tee -a /var/log/zfs-test-prep.log >/dev/console) 2>&1
echo "zfs-test-prep: start"

have_route() { ip -4 route | grep -q '^default'; }
for _ in $(seq 1 20); do have_route && break; sleep 1; done
if ! have_route; then
  for dev in $(ls /sys/class/net); do
    [ -e "/sys/class/net/$dev/device" ] || continue
    ip link set "$dev" up
    dhcpcd -4 -w -t 60 "$dev" && break
  done
fi

# Fixed IP from the kernel command line (zfstest.ip=<cidr> zfstest.gw= zfstest.dns= zfstest.domain=).
# The DHCP server does not reliably hand out the reserved address (client ID changes per boot).
arg() { tr ' ' '\n' < /proc/cmdline | sed -n "s/^zfstest\.$1=//p"; }
IP=$(arg ip); GW=$(arg gw); DNS=$(arg dns); DOMAIN=$(arg domain)
if [ -n "$IP" ]; then
  dev=$(ip -4 route show default | awk '{print $5; exit}')
  [ -n "$dev" ] || dev=$(for d in /sys/class/net/*; do [ -e "$d/device" ] && basename "$d"; done | head -n1)
  pkill dhcpcd || true
  cat > /etc/network/interfaces <<EOT
auto lo
iface lo inet loopback

auto $dev
iface $dev inet static
    address $IP
    gateway $GW
EOT
  ip -4 addr flush dev "$dev"
  ip link set "$dev" up
  ip addr add "$IP" dev "$dev"
  ip route replace default via "$GW"
  { [ -n "$DOMAIN" ] && echo "search $DOMAIN"; echo "nameserver ${DNS:-$GW}"; } > /etc/resolv.conf
fi
for _ in $(seq 1 60); do getent hosts deb.debian.org >/dev/null && break; sleep 2; done

export DEBIAN_FRONTEND=noninteractive
for _ in 1 2 3; do apt-get update && break; sleep 5; done

# Run do_ssh.sh unchanged; a pipe on stdin selects its non-interactive branch (no passwd prompt).
true | bash "$MED/do_ssh.sh"

install -d -m 0700 -o ansible -g ansible /home/ansible/.ssh
install -m 0600 -o ansible -g ansible "$MED/authorized_keys" /home/ansible/.ssh/authorized_keys
systemctl enable --now ssh

touch /run/zfs-test-ready
echo "zfs-test-prep: READY $(hostname) $(hostname -I)"
