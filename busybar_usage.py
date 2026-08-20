#!/usr/bin/env python3
"""Mac system monitor: CPU, used memory, and available memory as live bars using busylib-py.
   Modified version of https://github.com/maxswinkels/busybar-apps/tree/main/apps/mac-monitor
   This sticks to more memory based stuff and allows a delay argument

    python app.py                        # BUSY Bar over USB (always 10.0.4.20)
    python app.py --host 127.0.0.1:8080  # emulator or a Wi-Fi bar
    python app.py --delay 1.5            # set a custom update delay in seconds
"""
import subprocess
import sys
import time
import argparse
import os
import re
from busylib import BusyBar, types

APP = "mac-monitor"

# ---------------------------------------------------------------------------
# System metrics
# ---------------------------------------------------------------------------

_last = {"cpu": 0.0, "mem": 0.0}

def _run(*args):
    """Run a command and return stdout, or '' on failure."""
    try:
        r = subprocess.run(list(args), capture_output=True, text=True, timeout=3)
        return r.stdout
    except Exception:
        return ""

def _cpu_pct():
    """Return CPU % (0-100) as a float, capped at 100."""
    try:
        ps_out = _run("ps", "-A", "-o", "%cpu")
        total = sum(float(l) for l in ps_out.splitlines() if l.strip() not in ("", "%CPU"))
        ncpu_out = _run("sysctl", "-n", "hw.ncpu").strip()
        ncpu = int(ncpu_out) if ncpu_out else 1
        return min(100.0, total / max(ncpu, 1))
    except Exception:
        return _last["cpu"]

def _mem_pct():
    """Return used RAM % (0-100) as a float."""
    try:
        vm = _run("vm_stat")
        page_size = 4096
        for line in vm.splitlines():
            if "page size of" in line:
                parts = line.split()
                idx = parts.index("of") + 1
                page_size = int(parts[idx])
                break

        def _pages(key):
            for line in vm.splitlines():
                if line.startswith(key):
                    val = line.split(":")[1].strip().rstrip(".")
                    return int(val)
            return 0

        active = _pages("Pages active")
        wired = _pages("Pages wired down")
        compressed = _pages("Pages occupied by compressor")
        used_bytes = (active + wired + compressed) * page_size

        memsize_out = _run("sysctl", "-n", "hw.memsize").strip()
        total_bytes = int(memsize_out) if memsize_out else 1
        return min(100.0, used_bytes / total_bytes * 100.0)
    except Exception:
        return _last["mem"]

def get_macos_memory():
    """Returns (available_gb, total_gb)"""
    try:
        # 1. Get Total Physical Memory
        page_size = os.sysconf('SC_PAGE_SIZE')
        phys_pages = os.sysconf('SC_PHYS_PAGES')
        total_mem_bytes = page_size * phys_pages
        
        # 2. Get Available Memory via vm_stat
        vm_output = subprocess.check_output(['vm_stat']).decode('utf-8')
        vm_lines = vm_output.split('\n')
        
        stats = {}
        for line in vm_lines:
            match = re.match(r'Pages\s+([^:]+):\s+(\d+)\.', line)
            if match:
                stats[match.group(1).strip()] = int(match.group(2))
                
        # Available memory on macOS is roughly (Pages free + Pages inactive) * page size
        free_pages = stats.get('free', 0)
        inactive_pages = stats.get('inactive', 0)
        available_mem_bytes = (free_pages + inactive_pages) * page_size
        
        # Convert to Gigabytes
        total_gb = total_mem_bytes / (1024**3)
        available_gb = available_mem_bytes / (1024**3)
        
        return available_gb, total_gb
    except Exception:
        return 0.0, 1.0

# ---------------------------------------------------------------------------
# Display Logic using busylib
# ---------------------------------------------------------------------------

def _color(pct, invert=False):
    """Green / orange / red based on percentage. Mapped to text color names."""
    if invert:
        # For Available Memory: lower is worse
        if pct <= 10:
            return "red"
        if pct <= 30:
            return "orange"
        return "green"
    else:
        # For CPU / Used Memory: higher is worse
        if pct >= 90:
            return "red"
        if pct >= 70:
            return "orange"
        return "green"

def tick(bb: BusyBar):
    cpu = _cpu_pct()
    mem = _mem_pct()
    avail_gb, total_gb = get_macos_memory()
    
    avl_pct = (avail_gb / total_gb * 100.0) if total_gb > 0 else 0.0

    _last["cpu"] = cpu
    _last["mem"] = mem

    elements = []

    # Fits the 16px height constraint: Y=0, Y=5, Y=10
    for row_y, label, pct, frac, value_str, invert in (
        (0,  "CPU", cpu, cpu / 100.0, f"{round(cpu)}%", False),
        (5,  "MEM", mem, mem / 100.0, f"{round(mem)}%", False),
        (10, "AVL", avl_pct, avl_pct / 100.0, f"{avail_gb:.1f}G", True),
    ):
        col = _color(pct, invert)

        # 1. Label on the far left (approx 14px wide)
        elements.append(
            types.TextElement(
                id=f"{label.lower()}-label",
                type="text",
                x=0, 
                y=row_y,
                text=label,
                font="tiny",
                color="white"
            )
        )

        # 2. Text-based Progress Bar in the middle
        # Shrink to 6 characters so it fits the narrow 72px screen
        bar_len = 7
        filled = int(frac * bar_len)
        filled = max(0, min(bar_len, filled))
        bar_str = "[" + "=" * filled + "-" * (bar_len - filled) + "]"

        elements.append(
            types.TextElement(
                id=f"{label.lower()}-bar",
                type="text",
                x=18, # Starts right after the label
                y=row_y,
                text=bar_str,
                font="tiny",
                color=col
            )
        )

        # 3. Value text on the right
        # X=55 leaves enough pixels for the value text (easily fits "100%" or "1.5G")
        elements.append(
            types.TextElement(
                id=f"{label.lower()}-val",
                type="text",
                x=55, 
                y=row_y,
                text=value_str,
                font="tiny",
                color=col
            )
        )

    try:
        display_payload = types.DisplayElements(
            application_name=APP,
            elements=elements
        )
        bb.display_draw(display_payload)
    except Exception as e:
        print(f"Update failed: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Mac system monitor for Busy Bar.")
    parser.add_argument("--host", default="10.0.4.20", help="IP address of the Busy Bar or emulator.")
    # Added delay argument here:
    parser.add_argument("--delay", type=float, default=0.25, help="Update delay in seconds.")
    args = parser.parse_args()

    print(f"mac_monitor → {args.host} (Updating every {args.delay}s, Ctrl-C to stop)")
    
    # Initialize busylib client
    bb = BusyBar(args.host)
    bb.display_clear()
    
    try:
        while True:
            tick(bb)
            # Replaced hardcoded sleep with user-defined delay
            time.sleep(args.delay)
    except KeyboardInterrupt:
        print("\nstopped.")
