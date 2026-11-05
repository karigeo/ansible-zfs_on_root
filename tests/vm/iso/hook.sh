#!/bin/sh
# live-config hook (live-config.hooks=file://...): runs early in boot, so only
# queue the prep script as a transient unit that waits for the network.
systemd-run --no-block --unit=zfs-test-prep \
  -p After=network-online.target -p Wants=network-online.target \
  /bin/bash /run/live/medium/zfs-test/prep.sh
