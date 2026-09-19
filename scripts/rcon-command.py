#!/usr/bin/env python3
import os
import socket
import struct
import sys


SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0


def packet(request_id, packet_type, payload):
    data = payload.encode("utf-8") + b"\x00\x00"
    body = struct.pack("<ii", request_id, packet_type) + data
    return struct.pack("<i", len(body)) + body


def read_packet(sock):
    size_data = sock.recv(4)
    if len(size_data) != 4:
        raise RuntimeError("failed to read packet size")
    size = struct.unpack("<i", size_data)[0]
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("unexpected eof")
        data += chunk
    request_id, packet_type = struct.unpack("<ii", data[:8])
    payload = data[8:-2].decode("utf-8", errors="replace")
    return request_id, packet_type, payload


def main():
    if len(sys.argv) < 2:
        print("usage: rcon-command.py <command>", file=sys.stderr)
        return 2
    host = os.environ.get("RCON_HOST", "127.0.0.1")
    port = int(os.environ.get("RCON_PORT", "25575"))
    password = os.environ.get("RCON_PASSWORD")
    if not password:
        password_file = os.environ.get("RCON_PASSWORD_FILE", "/etc/minecraft/secrets/rcon_password")
        with open(password_file, encoding="utf-8") as handle:
            password = handle.read().strip()
    command = " ".join(sys.argv[1:])
    with socket.create_connection((host, port), timeout=10) as sock:
        sock.sendall(packet(1, SERVERDATA_AUTH, password))
        request_id, _, _ = read_packet(sock)
        if request_id == -1:
            raise RuntimeError("RCON authentication failed")
        sock.sendall(packet(2, SERVERDATA_EXECCOMMAND, command))
        _, packet_type, response = read_packet(sock)
        if packet_type != SERVERDATA_RESPONSE_VALUE:
            raise RuntimeError("unexpected RCON response")
        print(response)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
