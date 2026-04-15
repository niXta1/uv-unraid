#!/bin/bash
#
# build-plg.sh — regenerate plugins/uv.plg from the source/ tree.
#
# The canonical source of every file that ships inside the plugin lives under
# source/usr/local/emhttp/plugins/uv/. This script embeds each of those files
# as a <FILE Name="…"><INLINE><![CDATA[…]]></INLINE></FILE> block in the
# generated plugins/uv.plg, so the .plg itself is the single artifact Unraid
# needs to download.
#
# Usage:
#   scripts/build-plg.sh [VERSION]
#
# VERSION defaults to today's date in YYYY.MM.DD form (Unraid's convention).

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=${1:-$(date +%Y.%m.%d)}
OUT=plugins/uv.plg
SRC_ROOT=source
PLUGIN_SRC=${SRC_ROOT}/usr/local/emhttp/plugins/uv

if [[ ! -d ${PLUGIN_SRC} ]]; then
  echo "error: ${PLUGIN_SRC} not found" >&2
  exit 1
fi

mkdir -p plugins

emit_file_block() {
  local src=$1
  local mode=$2
  # Strip the leading SRC_ROOT/ to get the absolute on-target path.
  local dest=/${src#"${SRC_ROOT}/"}

  # CDATA cannot contain the literal sequence "]]>". Abort if a source file
  # does — callers must rewrite the content to avoid the sequence.
  if grep -q ']]>' "$src"; then
    echo "error: $src contains ']]>' which breaks CDATA" >&2
    exit 1
  fi

  cat <<EOF

<FILE Name="${dest}" Mode="${mode}">
<INLINE>
<![CDATA[
EOF
  cat "$src"
  cat <<'EOF'
]]>
</INLINE>
</FILE>
EOF
}

{
  cat <<EOF
<?xml version='1.0' standalone='yes'?>

<!DOCTYPE PLUGIN [
<!ENTITY name      "uv">
<!ENTITY author    "nixta1">
<!ENTITY version   "${VERSION}">
<!ENTITY launch    "Settings/uv">
<!ENTITY pluginURL "https://raw.githubusercontent.com/nixta1/uv-unraid/main/plugins/&name;.plg">
<!ENTITY emhttp    "/usr/local/emhttp/plugins/&name;">
<!ENTITY plgPath   "/boot/config/plugins/&name;">
]>

<PLUGIN
  name="&name;"
  author="&author;"
  version="&version;"
  launch="&launch;"
  pluginURL="&pluginURL;"
  min="6.11.0"
  support="https://github.com/nixta1/uv-unraid/issues">

<CHANGES>
##&name;

###${VERSION}
- Generated from source/ by scripts/build-plg.sh
- Installs uv + uvx from the Astral GitHub releases
- Caches the binary on /boot/config/plugins/&name;/bin/ across reboots
- Adds a Settings page showing the installed version
</CHANGES>

<!-- ==========================================================
     webGUI files (inlined from source/)
     ========================================================== -->
EOF

  # Every text file under source/ becomes a <FILE Name="…"> block. Shell
  # scripts need mode 0755 so they're executable; everything else is 0644.
  while IFS= read -r -d '' f; do
    case $f in
      *.sh) emit_file_block "$f" "0755" ;;
      *)    emit_file_block "$f" "0644" ;;
    esac
  done < <(find "${PLUGIN_SRC}" -type f -print0 | sort -z)

  cat <<'EOF'

<!-- ==========================================================
     Install: runs on plugin install and on every boot.
     ========================================================== -->
<FILE Run="/bin/bash">
<INLINE>
<![CDATA[
set -e
# Ensure the script is executable even on filesystems that ignore Mode=.
chmod 0755 /usr/local/emhttp/plugins/uv/scripts/install_uv.sh
chmod 0755 /usr/local/emhttp/plugins/uv/scripts/remove_uv.sh

/usr/local/emhttp/plugins/uv/scripts/install_uv.sh || true

echo ""
echo "-----------------------------------------------------------"
echo " Plugin uv is installed."
if command -v uv >/dev/null 2>&1; then
  echo " $(uv --version 2>/dev/null || echo 'uv present')"
fi
echo " See Settings -> uv in the webGUI for status."
echo "-----------------------------------------------------------"
echo ""
]]>
</INLINE>
</FILE>

<!-- ==========================================================
     Remove: runs when the user uninstalls the plugin.
     ========================================================== -->
<FILE Run="/bin/bash" Method="remove">
<INLINE>
<![CDATA[
if [[ -x /usr/local/emhttp/plugins/uv/scripts/remove_uv.sh ]]; then
  /usr/local/emhttp/plugins/uv/scripts/remove_uv.sh
else
  rm -f /usr/local/bin/uv /usr/local/bin/uvx
  rm -rf /boot/config/plugins/uv
  rm -rf /usr/local/emhttp/plugins/uv
fi
echo ""
echo "-----------------------------------------------------------"
echo " Plugin uv has been removed."
echo "-----------------------------------------------------------"
echo ""
]]>
</INLINE>
</FILE>

</PLUGIN>
EOF
} > "${OUT}"

echo "wrote ${OUT} (version ${VERSION})"
