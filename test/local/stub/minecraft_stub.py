#!/usr/bin/env python3
"""Stand-in for a running Paper server in local tests.

Implements just enough of two wire protocols for our own scripts to treat
this as "the Minecraft server": the Server List Ping status protocol on
STUB_PORT (what scripts/minecraft-status.py talks to) and the Source RCON
protocol on STUB_RCON_PORT (what scripts/rcon-command.py talks to). No real
Paper JVM, no world, no plugins -- this is deliberate (see SPEC.md 12.5.5):
tests exercise our own script logic (locking, retention, backup/restore,
state transitions), not Paper's own startup behavior.

Every response here is intentionally the minimum that satisfies the exact
parsing our own scripts do -- mirror scripts/minecraft-status.py and
scripts/rcon-command.py if either changes.
"""
import json
import os
import socket
import struct
import sys
import threading


def varint_encode(value):
    out = b""
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out += struct.pack("B", byte | 0x80)
        else:
            out += struct.pack("B", byte)
            return out


def varint_decode(recv_byte):
    value = 0
    shift = 0
    while True:
        data = recv_byte()
        byte = data[0]
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value
        shift += 7
        if shift > 35:
            raise RuntimeError("varint too large")


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise RuntimeError("unexpected eof")
        data += chunk
    return data


def status_packet(payload_dict):
    body = json.dumps(payload_dict).encode("utf-8")
    inner = varint_encode(len(body)) + body
    packet_body = varint_encode(0) + inner  # packet id 0 = Status Response
    return varint_encode(len(packet_body)) + packet_body


def handle_status_connection(conn):
    with conn:
        # Handshake packet: we don't need any of its fields, just consume it.
        length = varint_decode(lambda: recv_exact(conn, 1))
        recv_exact(conn, length)
        # Status Request packet (empty payload): consume and ignore.
        length = varint_decode(lambda: recv_exact(conn, 1))
        recv_exact(conn, length)

        online_file = "/tmp/minecraft-stub-online"
        if os.path.exists(online_file):
            with open(online_file, encoding="utf-8") as handle:
                online = int(handle.read().strip())
        else:
            online = int(os.environ.get("STUB_ONLINE_PLAYERS", "0"))
        max_players = int(os.environ.get("STUB_MAX_PLAYERS", "5"))
        motd = os.environ.get("STUB_MOTD", "local test stub")
        version_name = os.environ.get("STUB_VERSION_NAME", "Paper 0.0-test")
        protocol = int(os.environ.get("STUB_PROTOCOL", "1"))

        payload = {
            "description": motd,
            "players": {"online": online, "max": max_players},
            "version": {"name": version_name, "protocol": protocol},
        }
        conn.sendall(status_packet(payload))


def run_status_server(host, port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((host, port))
        listener.listen(8)
        while True:
            conn, _ = listener.accept()
            threading.Thread(target=handle_status_connection, args=(conn,), daemon=True).start()


# --- Source RCON (mirrors scripts/rcon-command.py's packet framing) ---

SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0


def rcon_packet(request_id, packet_type, payload=""):
    data = payload.encode("utf-8") + b"\x00\x00"
    body = struct.pack("<ii", request_id, packet_type) + data
    return struct.pack("<i", len(body)) + body


def read_rcon_packet(sock):
    size = struct.unpack("<i", recv_exact(sock, 4))[0]
    data = recv_exact(sock, size)
    request_id, packet_type = struct.unpack("<ii", data[:8])
    payload = data[8:-2].decode("utf-8", errors="replace")
    return request_id, packet_type, payload


# Canned replies for the handful of commands our scripts actually send.
RCON_REPLIES = {
    "save-all flush": "Saved the game",
}


def handle_rcon_connection(conn):
    with conn:
        request_id, packet_type, _ = read_rcon_packet(conn)
        if packet_type != SERVERDATA_AUTH:
            return
        # Every real command port in this test stub accepts any password --
        # there is nothing behind it worth protecting, and rcon-command.py
        # only checks that the returned request_id isn't -1.
        conn.sendall(rcon_packet(request_id, SERVERDATA_AUTH_RESPONSE))

        while True:
            try:
                request_id, packet_type, payload = read_rcon_packet(conn)
            except RuntimeError:
                return
            if packet_type != SERVERDATA_EXECCOMMAND:
                continue
            with open("/tmp/minecraft-stub-rcon.log", "a", encoding="utf-8") as handle:
                handle.write(payload.strip() + "\n")
            if payload.strip().startswith("say ") and os.path.exists("/tmp/minecraft-stub-fail-say"):
                return
            reply = RCON_REPLIES.get(payload.strip(), "")
            conn.sendall(rcon_packet(request_id, SERVERDATA_RESPONSE_VALUE, reply))


def run_rcon_server(host, port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((host, port))
        listener.listen(8)
        while True:
            conn, _ = listener.accept()
            threading.Thread(target=handle_rcon_connection, args=(conn,), daemon=True).start()


def main():
    host = os.environ.get("STUB_HOST", "0.0.0.0")
    status_port = int(os.environ.get("STUB_PORT", "25565"))
    rcon_port = int(os.environ.get("STUB_RCON_PORT", "25575"))

    status_thread = threading.Thread(target=run_status_server, args=(host, status_port), daemon=True)
    rcon_thread = threading.Thread(target=run_rcon_server, args=(host, rcon_port), daemon=True)
    status_thread.start()
    rcon_thread.start()
    print(f"minecraft-stub listening: status={host}:{status_port} rcon={host}:{rcon_port}", flush=True)
    status_thread.join()
    rcon_thread.join()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
