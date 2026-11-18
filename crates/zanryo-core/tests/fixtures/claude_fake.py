#!/usr/bin/python3
"""Offline PTY fixture. No network, credentials, filesystem writes or children."""
import datetime
import os
import signal
import sys
import time
import tty

tty.setraw(sys.stdin.fileno())
mode = os.path.basename(sys.argv[0])

def emit(text):
    sys.stdout.write(text.replace("\n", "\r\n"))
    sys.stdout.flush()

def read_exact(wanted):
    actual = b""
    while len(actual) < len(wanted):
        part = os.read(sys.stdin.fileno(), len(wanted) - len(actual))
        if not part:
            sys.exit(8)
        actual += part
    if actual != wanted:
        sys.exit(9)

def prompt():
    emit("\x1b[2J\x1b[HClaude Code v2.1.282\nSafe mode: customizations disabled\nmanual mode on\n$")

if mode == "auth":
    emit("Do you trust this folder?\n")
    time.sleep(60)
elif mode == "timeout":
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    time.sleep(60)
else:
    prompt()
    read_exact(b"/usage\r")
    now = datetime.datetime.now(datetime.timezone.utc)
    short = (now + datetime.timedelta(hours=1)).strftime("%-I:%M%p").lower()
    week = now + datetime.timedelta(days=2)
    reset = week.strftime("%b %-d at ") + week.strftime("%-I:%M%p").lower()
    def usage(percent):
        if mode == "success-2.1.327":
            # Dialog shape of CLI 2.1.327: session stats instead of a
            # five-hour window, a Fable window, a contributions section and a
            # new key hint. The weekly value moves from 3% (cached) to 4%.
            weekly = percent - 30
            return ("\x1b[2J\x1b[HSettings  Status   Config   Usage   Stats\n"
                    "Session\nEstimated cost: $0.0000\n"
                    f"Current week (all models)\n{weekly}% {weekly}% used\nResets {reset} (UTC)\n"
                    f"Current week (Fable)\n0% 0% used\nResets {reset} (UTC)\n"
                    "What's contributing to your usage?\n"
                    "Approximate · sessions on this computer only\nScanning local sessions…\n"
                    "Usage credits\nUsage credits are off\n←/→ to switch · Esc to close")
        return ("\x1b[2J\x1b[HSettings  Status   Config   Usage   Stats\n"
                f"Current session\n{percent}% {percent}% used\nResets {short} (UTC)\n"
                f"Current week (all models)\n3% 3% used\nResets {reset} (UTC)\n"
                "Usage credits\nUsage credits are off\nEsc to cancel")
    emit(usage(33))
    if mode == "cache":
        time.sleep(60)
    else:
        emit("\nRefreshing…\n")
        if mode == "failure":
            emit("Error: refresh failed\n")
            time.sleep(60)
        else:
            emit(usage(34))
            read_exact(b"\x1b")
            prompt()
            read_exact(b"/exit\r")
            if mode == "exit-hang":
                signal.signal(signal.SIGHUP, signal.SIG_IGN)
                time.sleep(60)
