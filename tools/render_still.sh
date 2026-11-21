#!/usr/bin/env bash
# Render one still from the real game launch (DemoDirector takes the shot at frame 100).
# Usage: tools/render_still.sh <out.png> [WxH] [demo args...]   e.g. demo2 satchel recipes
# Note: 1280x720 is reliable; full-1080p readback currently exits early on this machine.
OUT="$1"; RES="${2:-1280x720}"; shift 2 || shift $#
GODOT="${GODOT:-/d/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
timeout 120 "$GODOT" --path "$(dirname "$0")/.." --resolution "$RES" -- "shot=$OUT" "$@" >/dev/null 2>&1
if [ -f "$OUT" ]; then echo "saved $OUT"; else echo "no image written"; fi
