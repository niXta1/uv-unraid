#!/bin/bash
#
# remove_uv.sh — remove the uv binaries, cache and webGUI files.
#
# Called from the <FILE Method="remove"> block of uv.plg when the user
# uninstalls the plugin from the Unraid Plugin Manager.
#
# This script is intentionally tolerant: any given rm may fail (file
# already gone, previous install was partial) and we still want the
# cleanup to complete. `set -u` is kept to catch typos in variable
# references; `set -e` and `pipefail` are NOT set because the plugin
# manager aborts the whole uninstall on a non-zero exit from an INLINE
# block, which is the opposite of what we want here.

set -u

PLUGIN=uv

echo "[uv] removing binaries from /usr/local/bin"
rm -f /usr/local/bin/uv /usr/local/bin/uvx 2>/dev/null || true

echo "[uv] removing cache directory /boot/config/plugins/${PLUGIN}"
rm -rf "/boot/config/plugins/${PLUGIN}" 2>/dev/null || true

echo "[uv] removing webGUI files /usr/local/emhttp/plugins/${PLUGIN}"
rm -rf "/usr/local/emhttp/plugins/${PLUGIN}" 2>/dev/null || true

echo "[uv] uninstalled."
exit 0
