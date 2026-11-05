# Sourced by the tests/vm scripts. Local settings and secrets live outside the
# repository in $ZFS_TEST_DIR (default ~/.config/claude-zfs-test), see README.md.
export ZFS_TEST_DIR=${ZFS_TEST_DIR:-$HOME/.config/claude-zfs-test}
TESTS_VM=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -r "$ZFS_TEST_DIR/vm.env" ] || { echo "missing $ZFS_TEST_DIR/vm.env (see tests/vm/vm.env.example)" >&2; exit 1; }
# shellcheck source=/dev/null
set -a; . "$ZFS_TEST_DIR/vm.env"; set +a
TEST_KEY=$ZFS_TEST_DIR/id_ed25519
LOGS=$ZFS_TEST_DIR/logs
mkdir -p "$LOGS"
SSH_OPTS=(-i "$TEST_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
