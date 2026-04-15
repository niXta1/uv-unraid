#!/bin/bash
#
# remove_uv.sh — remove the uv binaries, cache and webGUI files.
#
# Called from the <FILE Method="remove"> block of uv.plg when the user
# uninstalls the plugin from the Unraid Plugin Manager.

set -euo pipefail

PLUGIN=uv

echo "[uv] removing binaries from /usr/local/bin"
rm -f /usr/local/bin/uv /usr/local/bin/uvx

echo "[uv] removing cache directory /boot/config/plugins/${PLUGIN}"
rm -rf "/boot/config/plugins/${PLUGIN}"

echo "[uv] removing webGUI files"
rm -rf "/usr/local/emhttp/plugins/${PLUGIN}"

echo "[uv] uninstalled."
