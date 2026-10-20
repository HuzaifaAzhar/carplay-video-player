"""Opens Car Video on the simulated CarPlay screen and photographs the app's demo walk-through.

The app (launched with -CarVideoDemo YES) logs "[Demo] shot <name>" when a screen is ready and
"[Demo] tap <x> <y>" (car points) when it wants a real tap. This script watches the app's diagnostics log,
takes a CarPlay screenshot for each shot, performs each tap through the Simulator window, and stops at
"[Demo] done".

Usage: drive.py <udid> <diagnostics.log> <out_dir> <label>
"""
import os
import re
import subprocess
import sys
import time

TITLE_BAR = 28  # Simulator window title bar height (points)


def run(cmd, check=False):
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def log_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def screenshot(udid, path):
    result = run(["xcrun", "simctl", "io", udid, "screenshot", "--display=external", path])
    return result.returncode == 0 and os.path.exists(path) and os.path.getsize(path) > 0


def image_size(path):
    from PIL import Image
    with Image.open(path) as img:
        return img.size


def window_geometry():
    script = '''
tell application "System Events"
    tell process "Simulator"
        repeat with w in every window
            if name of w contains "CarPlay" then
                set p to position of w
                set s to size of w
                return ((item 1 of p) as string) & " " & ((item 2 of p) as string) & " " & ((item 1 of s) as string) & " " & ((item 2 of s) as string)
            end if
        end repeat
    end tell
end tell
return ""
'''
    out = run(["osascript", "-e", script]).stdout.strip()
    try:
        x, y, w, h = (int(float(v)) for v in out.split())
        return x, y, w, h
    except ValueError:
        return None


def focus_carplay_window(geom):
    run(["osascript", "-e", 'tell application "Simulator" to activate',
         "-e", 'tell application "System Events" to tell process "Simulator" to perform action "AXRaise" of '
               '(first window whose name contains "CarPlay")'])
    x, y, w, _ = geom
    # Click the title bar: focuses the window without touching the CarPlay screen.
    run(["cliclick", f"c:{x + w // 2},{y + 10}"])
    time.sleep(0.8)


def to_desktop(px, py, img_w, img_h, geom):
    x, y, w, h = geom
    content_h = h - TITLE_BAR
    return int(x + px * w / img_w), int(y + TITLE_BAR + py * content_h / img_h)


def find_icon(path):
    """Centre of the orange Car Video icon in a CarPlay screenshot (pixels), skipping the dock on the left."""
    from PIL import Image
    img = Image.open(path).convert("RGB")
    width, height = img.size
    px = img.load()
    xs, ys = [], []
    # The dock is about 50 pt wide whatever the screen size.
    dock = int(min(width * 0.14, 120))
    for yy in range(0, height, 2):
        for xx in range(dock, width, 2):
            r, g, b = px[xx, yy]
            if r > 200 and 60 < g < 200 and b < 80 and r - b > 150:
                xs.append(xx)
                ys.append(yy)
    print(f"  orange pixels: {len(xs)} in {width}x{height}")
    if len(xs) < 120:
        return None
    xs.sort()
    ys.sort()
    return xs[len(xs) // 2], ys[len(ys) // 2]


def main():
    udid, log_path, out_dir, label = sys.argv[1:5]
    os.makedirs(out_dir, exist_ok=True)
    processed = len(log_lines(log_path))
    scale = 2.0
    shot_index = 0
    started = False
    deadline = time.time() + 240
    # Give up early if the app never opens on the car screen.
    open_deadline = time.time() + 60
    next_icon_try = time.time() + 4
    icon_attempts = 0
    pending_tap = None

    while time.time() < deadline and (started or time.time() < open_deadline):
        lines = log_lines(log_path)
        new, processed = lines[processed:], len(lines)
        for line in new:
            if "[Car]" in line or "[Demo]" in line or "[Web]" in line or "[Player]" in line:
                print("  app:", line)
            m = re.search(r"\[Demo\] (\w+)\s*(.*)$", line)
            if not m:
                continue
            kind, rest = m.group(1), m.group(2).strip()
            if kind == "start":
                started = True
                sm = re.search(r"scale ([0-9.]+)", rest)
                if sm:
                    scale = float(sm.group(1))
            elif kind == "shot":
                shot_index += 1
                name = re.sub(r"[^a-z0-9-]+", "-", rest.lower())
                path = os.path.join(out_dir, f"{label}-{shot_index:02d}-{name}.png")
                ok = screenshot(udid, path)
                print(f"  shot {name}: {'saved' if ok else 'FAILED'}")
            elif kind == "tap":
                tx, ty = (float(v) for v in rest.split()[:2])
                pending_tap = (tx, ty)
            elif kind == "done":
                print("  demo finished")
                return 0

        if pending_tap:
            tx, ty = pending_tap
            pending_tap = None
            probe = os.path.join(out_dir, f"{label}-tap-probe.png")
            geom = window_geometry()
            if geom and screenshot(udid, probe):
                img_w, img_h = image_size(probe)
                dx, dy = to_desktop(tx * scale, ty * scale, img_w, img_h, geom)
                print(f"  tapping car point {tx:.0f},{ty:.0f} -> desktop {dx},{dy}")
                focus_carplay_window(geom)
                run(["cliclick", f"c:{dx},{dy}"])
                for _ in range(8):
                    time.sleep(0.5)
                    if any("touch ok" in l for l in log_lines(log_path)[-20:]):
                        break
                else:
                    print("  no response yet; trying a press-and-hold click")
                    run(["cliclick", f"dd:{dx},{dy}", "w:150", f"du:{dx},{dy}"])
                os.remove(probe)

        if not started and time.time() >= next_icon_try and icon_attempts < 4:
            icon_attempts += 1
            next_icon_try = time.time() + 12
            probe = os.path.join(out_dir, f"{label}-home-{icon_attempts}.png")
            geom = window_geometry()
            if geom and screenshot(udid, probe):
                spot = find_icon(probe)
                if spot:
                    img_w, img_h = image_size(probe)
                    dx, dy = to_desktop(spot[0], spot[1], img_w, img_h, geom)
                    print(f"  app icon at {spot} -> desktop {dx},{dy}")
                    focus_carplay_window(geom)
                    run(["cliclick", f"c:{dx},{dy}"])
                    time.sleep(3)
                    if not any("Car screen connected" in l for l in log_lines(log_path)[processed:]):
                        run(["cliclick", f"dd:{dx},{dy}", "w:150", f"du:{dx},{dy}"])
                    run(["screencapture", "-x", os.path.join(out_dir, f"{label}-home-{icon_attempts}-desktop.png")])
                else:
                    # Not on this page of the CarPlay home screen: swipe to the next one.
                    x, y, w, h = geom
                    cy = y + TITLE_BAR + (h - TITLE_BAR) // 2
                    focus_carplay_window(geom)
                    run(["cliclick", f"dd:{x + int(w * 0.8)},{cy}", f"m:{x + int(w * 0.2)},{cy}", f"du:{x + int(w * 0.2)},{cy}"])
            else:
                print("  no CarPlay window or screenshot yet")
        time.sleep(0.5)

    print("  timed out" + ("" if started else " (the app never opened on the car screen)"))
    screenshot(udid, os.path.join(out_dir, f"{label}-99-timeout.png"))
    return 1


if __name__ == "__main__":
    sys.exit(main())
