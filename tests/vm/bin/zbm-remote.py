"""Drive "zbm" over dropbear with a pty and enter the native passphrase.
Usage: zbm-remote <ip> <passphrase>. Prints the session output."""
import sys, os, pexpect
ip, pw = sys.argv[1], sys.argv[2]
key = os.path.join(os.environ["ZFS_TEST_DIR"], "id_ed25519")
child = pexpect.spawn("ssh", ["-tt", "-i", key, "-p", "222", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
                              "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", f"root@{ip}", "zbm"],
                      encoding="utf-8", codec_errors="replace", timeout=90, dimensions=(40, 140))
child.logfile_read = sys.stdout
i = child.expect([r"(?i)passphrase for '[^']+'", r"must be initialized", pexpect.EOF, pexpect.TIMEOUT])
print(f"\n### first match: {i}", flush=True)
if i == 0:
    child.sendline(pw)
    j = child.expect([r"(?i)boot", pexpect.EOF, pexpect.TIMEOUT], timeout=60)
    print(f"\n### after passphrase: {j}", flush=True)
    if j == 0:
        child.send("\r")  # boot the default (selected) environment
        child.expect([pexpect.EOF, pexpect.TIMEOUT], timeout=60)
child.close()
