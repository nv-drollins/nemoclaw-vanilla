#!/usr/bin/env python3
import argparse
import selectors
import socket
import threading


def bridge(client, target_host, target_port):
    upstream = socket.create_connection((target_host, target_port), timeout=10)
    client.setblocking(False)
    upstream.setblocking(False)

    selector = selectors.DefaultSelector()
    selector.register(client, selectors.EVENT_READ, upstream)
    selector.register(upstream, selectors.EVENT_READ, client)

    sockets = (client, upstream)
    try:
        while True:
            events = selector.select(timeout=60)
            if not events:
                break
            for key, _ in events:
                src = key.fileobj
                dst = key.data
                try:
                    data = src.recv(65536)
                except BlockingIOError:
                    continue
                if not data:
                    return
                dst.sendall(data)
    finally:
        for sock in sockets:
            try:
                selector.unregister(sock)
            except Exception:
                pass
            try:
                sock.close()
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(description="Tiny TCP proxy for the OpenClaw dashboard.")
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-port", type=int, required=True)
    args = parser.parse_args()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.listen_host, args.listen_port))
    server.listen(128)

    while True:
        client, _ = server.accept()
        thread = threading.Thread(
            target=bridge,
            args=(client, args.target_host, args.target_port),
            daemon=True,
        )
        thread.start()


if __name__ == "__main__":
    main()

