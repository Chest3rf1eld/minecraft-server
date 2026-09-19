#!/usr/bin/env python3
import json
import socket
import struct
import sys


def varint(value):
    out = b""
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out += struct.pack("B", byte | 0x80)
        else:
            out += struct.pack("B", byte)
            return out


def read_varint(sock):
    value = 0
    shift = 0
    while True:
        data = sock.recv(1)
        if not data:
            raise RuntimeError("unexpected eof")
        byte = data[0]
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value
        shift += 7
        if shift > 35:
            raise RuntimeError("varint too large")


def packet(packet_id, payload):
    body = varint(packet_id) + payload
    return varint(len(body)) + body


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 25565
    with socket.create_connection((host, port), timeout=5) as sock:
        encoded_host = host.encode("utf-8")
        handshake = (
            varint(765)
            + varint(len(encoded_host))
            + encoded_host
            + struct.pack(">H", port)
            + varint(1)
        )
        sock.sendall(packet(0, handshake))
        sock.sendall(packet(0, b""))
        _ = read_varint(sock)
        packet_id = read_varint(sock)
        if packet_id != 0:
            raise RuntimeError(f"unexpected packet id {packet_id}")
        length = read_varint(sock)
        data = b""
        while len(data) < length:
            data += sock.recv(length - len(data))
        print(json.dumps(json.loads(data.decode("utf-8")), ensure_ascii=False))


if __name__ == "__main__":
    main()
