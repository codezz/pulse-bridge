#!/usr/bin/env python3
"""Split FFF7 responses from a listen log into per-record rows.

  analyze.py LOG.jsonl [--size N]

Responses are concatenated per command, then cut into records that start with
the command opcode. --size forces a fixed record length instead.
"""
import argparse
import json
from collections import defaultdict

FFF7 = "0000fff7-0000-1000-8000-00805f9b34fb"


def responses(path):
    """Concatenate FFF7 bytes per opcode, ignoring unsolicited 0x16 events."""
    out = defaultdict(bytearray)
    for line in open(path):
        e = json.loads(line)
        if e["type"] == "notify" and e["char"] == FFF7:
            data = bytes.fromhex(e["hex"])
            if data[0] != 0x16:
                out[data[0]] += data
    return out


def records(blob: bytes, size: int):
    return [blob[i:i + size] for i in range(0, len(blob), size)]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("log")
    p.add_argument("--size", type=int)
    args = p.parse_args()
    for op, blob in responses(args.log).items():
        # Guess record size from the distance to the next "op idx+1" marker
        size = args.size
        if not size:
            nxt = blob.find(bytes([op, 0x01]), 1)
            size = nxt if nxt > 0 else len(blob)
        print(f"== opcode 0x{op:02x}  bytes={len(blob)}  record={size}")
        for r in records(bytes(blob), size):
            print("  " + r.hex(" "))


if __name__ == "__main__":
    main()
