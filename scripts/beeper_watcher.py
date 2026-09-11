#!/usr/bin/env python3
import json
import os
import time
import urllib.request

FLAG_FILE = os.environ.get("TS35_BEEPER_FLAG", "/home/biqu/beeper_enabled")
MARKER = "BEEPER_TOGGLE_EVENT"
MOONRAKER_URL = "http://localhost:7125/server/gcode_store?count=5"


def read_flag():
    try:
        with open(FLAG_FILE) as f:
            return f.read().strip()
    except FileNotFoundError:
        return "1"


def write_flag(value):
    tmp = FLAG_FILE + ".tmp"
    with open(tmp, "w") as f:
        f.write(value)
    os.replace(tmp, FLAG_FILE)


def toggle():
    new = "0" if read_flag() == "1" else "1"
    write_flag(new)
    print(f"Beeper flag toggled -> {new}", flush=True)


if not os.path.exists(FLAG_FILE):
    write_flag("1")

# Do not replay old messages after boot.
last_seen_time = time.time()
print("Novin3dp beeper watcher running.", flush=True)

while True:
    try:
        with urllib.request.urlopen(MOONRAKER_URL, timeout=2) as response:
            data = json.load(response)
        entries = data.get("result", {}).get("gcode_store", [])
        newest = last_seen_time
        for entry in sorted(entries, key=lambda item: item.get("time", 0)):
            timestamp = float(entry.get("time", 0) or 0)
            message = str(entry.get("message", ""))
            if timestamp > last_seen_time and MARKER in message:
                toggle()
            newest = max(newest, timestamp)
        last_seen_time = newest
    except Exception as exc:
        print(f"watcher error: {exc}", flush=True)
    time.sleep(0.5)
