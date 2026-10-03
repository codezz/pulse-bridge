#!/usr/bin/env python3
"""BLE probe for reverse engineering the Pulse/Makina WS01A band.

Throwaway dev tool. Findings go to docs/protocol.md and get ported to the iOS app.

  probe.py scan [--seconds N]
  probe.py dump [--device ID]
  probe.py listen [--device ID] [--seconds N] [--write UUID=HEX ...]

`scan` remembers the chosen device in .device, so later commands need no --device.
"""
import argparse
import asyncio
import json
import sys
import time
from datetime import datetime
from pathlib import Path

from bleak import BleakClient, BleakScanner

ROOT = Path(__file__).resolve().parent
DEVICE_FILE = ROOT / ".device"
LOG_DIR = ROOT.parent.parent / "logs"


def now() -> str:
    return datetime.now().isoformat(timespec="milliseconds")


def fmt(data: bytes) -> str:
    return data.hex(" ")


def ascii_preview(data: bytes) -> str:
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data)


CMD_CHAR = "0000fff6-0000-1000-8000-00805f9b34fb"
# Opcodes that wipe or reboot the band; refuse to send them by accident
# Keep in sync with Opcode.forbidden in PulseKit (Command.swift).
DANGEROUS = {0x12, 0x2E, 0x61}
# History reads whose second byte 0x99 (or 0x09 for workouts) deletes that history.
HISTORY_OPCODES = {0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x5C, 0x60, 0x62, 0x66}


def is_dangerous(uuid: str, data: bytes) -> bool:
    """True for frames that would wipe, reset or delete data on the band."""
    if uuid.lower() != CMD_CHAR or not data:
        return False
    if data[0] in DANGEROUS:
        return True
    return data[0] in HISTORY_OPCODES and len(data) > 1 and data[1] in (0x99, 0x09)


def frame(hexdata: str) -> bytes:
    """JStyle frame: 15 bytes zero-padded + checksum (sum & 0xFF)."""
    body = bytes.fromhex(hexdata.replace(" ", "")).ljust(15, b"\0")[:15]
    return body + bytes([sum(body) & 0xFF])


def resolve_device(arg: str | None) -> str:
    if arg:
        return arg
    if DEVICE_FILE.exists():
        return DEVICE_FILE.read_text().strip()
    sys.exit("No device. Run `probe.py scan` first or pass --device.")


async def cmd_scan(args):
    print(f"Scanning {args.seconds}s...")
    found = await BleakScanner.discover(timeout=args.seconds, return_adv=True)
    rows = sorted(found.values(), key=lambda p: -p[1].rssi)
    for i, (dev, adv) in enumerate(rows):
        name = adv.local_name or dev.name or "?"
        print(f"[{i:2}] {dev.address}  rssi={adv.rssi:4}  name={name}")
        if adv.service_uuids:
            print(f"      services: {', '.join(adv.service_uuids)}")
        for cid, data in adv.manufacturer_data.items():
            print(f"      mfr 0x{cid:04x}: {fmt(data)}")
    # Auto-pick the first device whose name matches the filter
    if args.match:
        for dev, adv in rows:
            name = (adv.local_name or dev.name or "").lower()
            if args.match.lower() in name:
                DEVICE_FILE.write_text(dev.address)
                print(f"\nSaved device {dev.address} ({name}) to .device")
                break


async def cmd_dump(args):
    address = resolve_device(args.device)
    async with BleakClient(address) as client:
        print(f"Connected {address}  mtu={client.mtu_size}")
        for svc in client.services:
            print(f"\nSERVICE {svc.uuid}  ({svc.description})")
            for ch in svc.characteristics:
                props = ",".join(ch.properties)
                print(f"  CHAR {ch.uuid}  [{props}]  ({ch.description})  handle={ch.handle}")
                if "read" in ch.properties:
                    try:
                        val = await client.read_gatt_char(ch)
                        print(f"    value: {fmt(val)}  |{ascii_preview(val)}|")
                    except Exception as e:
                        print(f"    read error: {e}")
                for d in ch.descriptors:
                    try:
                        val = await client.read_gatt_descriptor(d.handle)
                        print(f"    DESC {d.uuid}: {fmt(val)}")
                    except Exception as e:
                        print(f"    DESC {d.uuid}: read error: {e}")


async def cmd_listen(args):
    address = resolve_device(args.device)
    LOG_DIR.mkdir(exist_ok=True)
    log_path = LOG_DIR / f"listen-{datetime.now():%Y%m%d-%H%M%S}.jsonl"
    log = log_path.open("w")

    def record(event: dict):
        event["t"] = now()
        log.write(json.dumps(event) + "\n")
        log.flush()

    async with BleakClient(address) as client:
        print(f"Connected {address}. Logging to {log_path}")

        def handler_for(uuid: str):
            def handler(_, data: bytearray):
                data = bytes(data)
                print(f"{now()}  {uuid[:8]}  {fmt(data)}  |{ascii_preview(data)}|")
                record({"type": "notify", "char": uuid, "hex": data.hex()})
            return handler

        for svc in client.services:
            for ch in svc.characteristics:
                if {"notify", "indicate"} & set(ch.properties):
                    try:
                        await client.start_notify(ch, handler_for(ch.uuid))
                        print(f"Subscribed {ch.uuid}")
                    except Exception as e:
                        print(f"Subscribe failed {ch.uuid}: {e}")

        writes = [s.split("=", 1) for s in args.write or []]
        writes += [(CMD_CHAR, frame(c).hex()) for c in args.cmd or []]
        for uuid, hexdata in writes:
            await asyncio.sleep(1.0)
            data = bytes.fromhex(hexdata.replace(" ", ""))
            if is_dangerous(uuid, data) and not args.force:
                sys.exit(f"Refusing dangerous opcode 0x{data[0]:02x} (use --force)")
            print(f"{now()}  WRITE {uuid[:8]}  {fmt(data)}")
            record({"type": "write", "char": uuid, "hex": data.hex()})
            await client.write_gatt_char(uuid, data, response=not args.no_response)

        end = time.monotonic() + args.seconds
        while time.monotonic() < end and client.is_connected:
            await asyncio.sleep(0.2)
    log.close()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("scan")
    s.add_argument("--seconds", type=float, default=8)
    s.add_argument("--match", help="save first device whose name contains this")

    for name in ("dump", "listen"):
        sp = sub.add_parser(name)
        sp.add_argument("--device")
        if name == "listen":
            sp.add_argument("--seconds", type=float, default=30)
            sp.add_argument("--write", action="append", metavar="UUID=HEX")
            sp.add_argument("--cmd", action="append", metavar="HEX", help="JStyle command, padded + checksummed, sent to FFF6")
            sp.add_argument("--no-response", action="store_true")
            sp.add_argument("--force", action="store_true")

    args = p.parse_args()
    asyncio.run({"scan": cmd_scan, "dump": cmd_dump, "listen": cmd_listen}[args.command](args))


if __name__ == "__main__":
    main()
