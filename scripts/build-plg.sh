#!/bin/bash
#
# build-plg.sh — regenerate plugins/uv.plg from the source/ tree.
#
# Every file under source/usr/local/emhttp/plugins/uv/ is embedded as a
#
#   <FILE Name="…" Mode="0644|0755">
#     <INLINE>…xml-escaped source bytes…</INLINE>
#   </FILE>
#
# block. The key design decisions here are driven by the Unraid plugin
# format docs at plugin-docs.mstrhakr.com and — more importantly — by
# surveying the .plg files of real Unraid 7.x plugins on GitHub
# (bergware/dynamix, Joly0/par2protect, Ac3sRwild/unraid-lsi-mon,
# dkaser/unraid-*, SimonFair/*, …):
#
#   * No CDATA. XML entity references (&name;, &emhttpLOC;, …) declared
#     in the DOCTYPE header are NOT expanded inside <![CDATA[…]]>, which
#     makes CDATA a trap for future edits even if the *current* sources
#     happen not to use any entities. We XML-escape &, <, > instead; the
#     plugin manager's parser will decode them back to the original bytes
#     before writing each file to disk. Joly0/par2protect's v7 plugin
#     confirms bare <INLINE> content with &emhttp; entity refs works.
#
#   * No Run= on <FILE Name> blocks. 650+ real-world .plg files use
#     <FILE Name="…"><INLINE>…</INLINE></FILE> without any Run attribute
#     to materialize a file on disk. Examples in the v7 cohort:
#       - Joly0/par2protect par2protect.plg:80 (min="7.0.0")
#       - Ac3sRwild/unraid-lsi-mon plugin/lsi-mon.plg:56 (min="7.0.0")
#       - bergware/dynamix dynamix.s3.sleep.plg:216 (still current).
#
#   * Mode= is a real attribute. Undocumented in mstrhakr's plugin-docs,
#     but actively used by bergware/dynamix on a Name+INLINE block
#     (Mode="0770" in dynamix.s3.sleep.plg). Using it here lets us skip
#     the post-install chmod dance entirely.
#
#   * The <CHANGES> block is extracted from CHANGELOG.md so there is a
#     single source of truth for the version history.
#
# Usage:
#   scripts/build-plg.sh [VERSION]
#
# VERSION defaults to the most recent "## [YYYY.MM.DD]" entry in
# CHANGELOG.md, or today's date if the changelog is missing/empty.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT=plugins/uv.plg
SRC_ROOT=source
PLUGIN_NAME=uv
PLUGIN_SRC=${SRC_ROOT}/usr/local/emhttp/plugins/${PLUGIN_NAME}
CHANGELOG=CHANGELOG.md

if [[ ! -d ${PLUGIN_SRC} ]]; then
  echo "error: ${PLUGIN_SRC} not found" >&2
  exit 1
fi

# Resolve version: argv[1] > latest CHANGELOG entry > today's date.
if [[ $# -gt 0 ]]; then
  VERSION=$1
elif [[ -f ${CHANGELOG} ]]; then
  VERSION=$(grep -Po '^## \[\K[0-9]{4}\.[0-9]{2}\.[0-9]{2}' "${CHANGELOG}" \
              | head -n1 || true)
  VERSION=${VERSION:-$(date +%Y.%m.%d)}
else
  VERSION=$(date +%Y.%m.%d)
fi

mkdir -p plugins

# ---------- helpers --------------------------------------------------------

# xml_escape: escape &, <, > on stdin. No CDATA, no entity preservation —
# source files must not contain XML entity references in text content.
xml_escape() {
  python3 -c '
import sys
s = sys.stdin.read()
s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
sys.stdout.write(s)
'
}

# extract_changes: pull the top-most "## [VERSION]" section out of
# CHANGELOG.md and reformat it for the <CHANGES> block. "### Added"
# subsection headers are stripped so the output contains bullets only
# (Unraid's Plugin Manager already uses ### for the version header).
extract_changes() {
  if [[ ! -f ${CHANGELOG} ]]; then
    printf '###%s\n- see CHANGELOG.md\n' "${VERSION}"
    return
  fi
  python3 - "${CHANGELOG}" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
out = []
started = False
for ln in text.splitlines():
    m = re.match(r"^## \[(?P<v>[0-9.]+)\]", ln)
    if m:
        if started:
            break
        started = True
        out.append("###" + m.group("v"))
        continue
    if not started:
        continue
    if ln.startswith("## "):
        break
    if re.match(r"^### ", ln):
        # Keep subsection title as a plain bullet header so the
        # Plugin Manager's markdown renderer doesn't collide with
        # Unraid's own "###VERSION" convention.
        title = ln[4:].strip()
        out.append("")
        out.append(f"**{title}**")
        continue
    out.append(ln)
# collapse runs of blank lines
cleaned = []
blank = False
for ln in out:
    if ln.strip() == "":
        if blank:
            continue
        blank = True
    else:
        blank = False
    cleaned.append(ln)
result = "\n".join(cleaned).rstrip()
# XML-escape: the CHANGELOG may legitimately contain `<FILE …>` or other
# angle-bracketed examples inside backticks. Without escaping, those land
# as literal tags inside <CHANGES> and break XML parsing.
result = (result
          .replace("&", "&amp;")
          .replace("<", "&lt;")
          .replace(">", "&gt;"))
print(result)
PY
}

emit_file_block() {
  local src=$1
  local dest=/${src#"${SRC_ROOT}/"}
  local mode
  case $src in
    *.sh)  mode=0755 ;;
    *)     mode=0644 ;;
  esac
  printf '\n<FILE Name="%s" Mode="%s">\n<INLINE>\n' "${dest}" "${mode}"
  xml_escape < "${src}"
  printf '</INLINE>\n</FILE>\n'
}

# verify_roundtrip: reparse the just-written plugins/uv.plg, extract every
# <FILE Name="…"><INLINE>…</INLINE></FILE> block, and byte-compare the
# decoded INLINE text against the matching file in source/. Any drift is
# a build-breaking error.
verify_roundtrip() {
  python3 - "${OUT}" "${SRC_ROOT}" <<'PY'
import sys, pathlib, xml.etree.ElementTree as ET

plg_path = pathlib.Path(sys.argv[1])
src_root = pathlib.Path(sys.argv[2])

tree = ET.parse(plg_path)
root = tree.getroot()

errors = []
seen = 0
for file_el in root.findall("FILE"):
    name = file_el.get("Name")
    if not name:
        continue
    inline = file_el.find("INLINE")
    if inline is None:
        errors.append(f"{name}: no <INLINE> child")
        continue
    embedded = inline.text or ""
    # We emit a newline immediately after <INLINE> for readability; strip it.
    if embedded.startswith("\n"):
        embedded = embedded[1:]

    rel = pathlib.Path(name).relative_to("/")
    src_path = src_root / rel
    if not src_path.exists():
        errors.append(f"{name}: source file {src_path} does not exist")
        continue
    original = src_path.read_text()
    if embedded != original:
        errors.append(
            f"{name}: roundtrip mismatch "
            f"(embedded={len(embedded)}B source={len(original)}B)"
        )
        for i, (a, b) in enumerate(zip(embedded, original)):
            if a != b:
                ctx_start = max(0, i - 20)
                errors.append(
                    f"  first diff at offset {i}: "
                    f"embedded={a!r} source={b!r} "
                    f"ctx={original[ctx_start:i+20]!r}"
                )
                break
        if len(embedded) != len(original):
            errors.append(
                f"  length differs by {len(embedded) - len(original)} bytes"
            )
    seen += 1

if errors:
    print("roundtrip verification FAILED:", file=sys.stderr)
    for e in errors:
        print("  " + e, file=sys.stderr)
    sys.exit(1)
print(f"verify: {seen} inlined files match source/ byte-for-byte")
PY
}

# ---------- template -------------------------------------------------------
#
# The quoted heredoc below contains literal XML with ENTITY references that
# will be expanded by the plugin manager's XML parser at install time —
# they MUST NOT be expanded by bash, hence <<'EOF_TEMPLATE_TAIL'. Literal
# ampersands, < and > in the install/remove INLINE bash blocks are manually
# XML-escaped (&amp;, &lt;, &gt;).

{
  cat <<EOF_TEMPLATE_HEAD
<?xml version='1.0' standalone='yes'?>

<!DOCTYPE PLUGIN [
<!ENTITY name       "${PLUGIN_NAME}">
<!ENTITY author     "nixta1">
<!ENTITY version    "${VERSION}">
<!ENTITY launch     "Settings/uv">
<!ENTITY gh         "https://github.com/nixta1/uv-unraid">
<!ENTITY pluginURL  "https://raw.githubusercontent.com/nixta1/uv-unraid/main/plugins/&name;.plg">
<!ENTITY readmeURL  "https://raw.githubusercontent.com/nixta1/uv-unraid/main/source/usr/local/emhttp/plugins/&name;/README.md">
<!ENTITY emhttpLOC  "/usr/local/emhttp/plugins/&name;">
<!ENTITY pluginLOC  "/boot/config/plugins/&name;">
]>

<PLUGIN
  name="&name;"
  author="&author;"
  version="&version;"
  launch="&launch;"
  pluginURL="&pluginURL;"
  project="&gh;"
  support="&gh;/issues"
  readme="&readmeURL;"
  icon="bolt"
  min="6.11.0">

<CHANGES>
##&name;

$(extract_changes)
</CHANGES>

<!-- ==========================================================
     webGUI files (inlined verbatim from source/)
     ========================================================== -->
EOF_TEMPLATE_HEAD

  while IFS= read -r -d '' f; do
    emit_file_block "$f"
  done < <(find "${PLUGIN_SRC}" -type f -print0 | sort -z)

  cat <<'EOF_TEMPLATE_TAIL'

<!-- ==========================================================
     Install: runs on plugin install and on every Unraid boot
     (installplg re-executes every .plg under /boot/config/plugins
     as part of init). Non-zero exits from an INLINE block abort
     the plugin install, so install_uv.sh failures are caught
     explicitly and logged rather than propagated — the cached
     binary (if any) will still be restored on the next boot.

     Script file modes come from the Mode="0755" attribute on the
     individual <FILE> blocks above; no explicit chmod is needed.
     ========================================================== -->
<FILE Run="/bin/bash">
<INLINE>
set -e

if ! &emhttpLOC;/scripts/install_uv.sh; then
  echo "[uv] install_uv.sh failed during plugin install" &gt;&amp;2
  echo "[uv] the plugin is still registered; use 'Settings -&gt; uv -&gt; Update now' once the network is available" &gt;&amp;2
fi

echo ""
echo "-----------------------------------------------------------"
echo " Plugin &name; &version; is installed."
if command -v uv &gt;/dev/null 2&gt;&amp;1; then
  echo " $(uv --version 2&gt;/dev/null || echo 'uv present')"
else
  echo " uv is not on PATH yet — check logs above."
fi
echo " See Settings -&gt; User Utilities -&gt; uv for status."
echo "-----------------------------------------------------------"
echo ""
</INLINE>
</FILE>

<!-- ==========================================================
     Remove: runs when the user uninstalls the plugin.
     Each rm is tolerant so a partial previous install still
     cleans up cleanly.
     ========================================================== -->
<FILE Run="/bin/bash" Method="remove">
<INLINE>
if [ -x &emhttpLOC;/scripts/remove_uv.sh ]; then
  &emhttpLOC;/scripts/remove_uv.sh || true
else
  rm -f  /usr/local/bin/uv /usr/local/bin/uvx 2&gt;/dev/null || true
  rm -rf &pluginLOC;                          2&gt;/dev/null || true
  rm -rf &emhttpLOC;                          2&gt;/dev/null || true
fi

echo ""
echo "-----------------------------------------------------------"
echo " Plugin &name; has been removed."
echo "-----------------------------------------------------------"
echo ""
</INLINE>
</FILE>

</PLUGIN>
EOF_TEMPLATE_TAIL
} > "${OUT}"

verify_roundtrip
echo "wrote ${OUT} (version ${VERSION})"
