"""VM console via the Proxmox API (vncproxy + vncwebsocket on port 8006).

Usage:
  pvecon shot FILE.png          screenshot of the VM console
  pvecon type TEXT              type text (no Enter)
  pvecon key KEY [KEY...]       press keys, e.g. enter, esc, ctrl-alt-del, f2
Never prints the API token or the VNC password.
"""
import asyncio
import json
import os
import socket
import ssl
import sys
import threading
import time
import urllib.parse
import urllib.request

CFG = os.environ.get("ZFS_TEST_DIR", os.path.expanduser("~/.config/claude-zfs-test"))
CERT_NAME = os.environ["PVE_CERT_NAME"]


def load_env():
    env = {}
    with open(os.path.join(CFG, "pve.env")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k] = v.strip().strip("'\"")
    return env


ENV = load_env()
HOSTPORT = ENV["PVE_URL"].split("://", 1)[1].rstrip("/")
IP, PORT = HOSTPORT.rsplit(":", 1)
PORT = int(PORT)
AUTH = f"PVEAPIToken={ENV['PVE_TOKEN_ID']}={ENV['PVE_TOKEN_SECRET']}"
BASE = f"/api2/json/nodes/{ENV['PVE_NODE']}/qemu/{ENV['PVE_VMID']}"


def ssl_ctx():
    ctx = ssl.create_default_context(cafile=os.path.join(CFG, "pve-root-ca.pem"))
    # The PVE root CA has no keyUsage extension, which Python's strict mode rejects.
    ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
    return ctx


def tls_socket():
    raw = socket.create_connection((IP, PORT), timeout=15)
    return raw


def api_post(path, data):
    # urllib with the cert name pinned to the IP
    import http.client

    conn = http.client.HTTPSConnection(CERT_NAME, PORT, context=ssl_ctx(), timeout=30)
    conn.sock = ssl_ctx().wrap_socket(tls_socket(), server_hostname=CERT_NAME)
    body = urllib.parse.urlencode(data)
    conn.request("POST", BASE + path, body=body,
                 headers={"Authorization": AUTH, "Content-Type": "application/x-www-form-urlencoded"})
    r = conn.getresponse()
    out = r.read()
    if r.status != 200:
        sys.exit(f"API error {r.status}: {out[:300]!r}")
    return json.loads(out)["data"]


def start_bridge():
    """Local TCP port <-> Proxmox vncwebsocket. Returns (local_port, vnc_password)."""
    import websockets.asyncio.client as wsc

    vnc = api_post("/vncproxy", {"websocket": 1, "generate-password": 1})
    q = urllib.parse.urlencode({"port": vnc["port"], "vncticket": vnc["ticket"]})
    uri = f"wss://{CERT_NAME}:{PORT}{BASE}/vncwebsocket?{q}"

    lsock = socket.socket()
    lsock.bind(("127.0.0.1", 0))
    lsock.listen(1)
    lport = lsock.getsockname()[1]

    async def run():
        loop = asyncio.get_running_loop()
        csock, _ = await loop.sock_accept(lsock)
        csock.setblocking(False)
        reader, writer = await asyncio.open_connection(sock=csock)
        async with wsc.connect(uri, sock=tls_socket(), ssl=ssl_ctx(), server_hostname=CERT_NAME,
                               additional_headers={"Authorization": AUTH},
                               subprotocols=["binary"], max_size=None, compression=None) as ws:
            async def up():
                while data := await reader.read(65536):
                    await ws.send(data)
                await ws.close()

            async def down():
                async for msg in ws:
                    writer.write(msg if isinstance(msg, bytes) else msg.encode())
                    await writer.drain()
                writer.close()

            await asyncio.gather(up(), down(), return_exceptions=True)

    threading.Thread(target=lambda: asyncio.run(run()), daemon=True).start()
    return lport, vnc["password"]


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("shot", "type", "key"):
        sys.exit(__doc__)
    from vncdotool import api

    lport, password = start_bridge()
    client = api.connect(f"127.0.0.1::{lport}", password=password, timeout=30)
    try:
        cmd, args = sys.argv[1], sys.argv[2:]
        if cmd == "shot":
            client.refreshScreen()
            time.sleep(0.5)
            client.captureScreen(args[0])
            print(args[0])
        elif cmd == "type":
            for ch in " ".join(args):
                client.keyPress(ch)
                time.sleep(0.03)
        else:
            for k in args:
                client.keyPress(k)
                time.sleep(0.2)
    finally:
        client.disconnect()
        api.shutdown()


if __name__ == "__main__":
    main()
