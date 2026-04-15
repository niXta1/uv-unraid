# uv-unraid

An [Unraid](https://unraid.net) plugin that installs [`uv`](https://github.com/astral-sh/uv) —
Astral's extremely fast Python package & project manager — on your Unraid server.

The plugin downloads the official `uv` (and `uvx`) binary from the Astral GitHub releases,
caches it on the USB boot flash so it survives reboots, and restores it into
`/usr/local/bin` every time the array comes up. A small Settings page in the Unraid
webGUI shows the currently installed version and lets you trigger an update.

## Features

- Installs `uv` and `uvx` from Astral's official release tarball.
- Caches the binary on the USB flash drive at `/boot/config/plugins/uv/bin/` so Unraid's
  tmpfs root doesn't need to re-download it on every reboot.
- Idempotent install script — re-runs safely, supports upgrading by deleting the cache.
- Settings page under **Settings → Other Settings → uv** showing the installed version,
  cache location and an "Update now" button.
- Clean uninstall that removes the binary, cache and webGUI files.

## Install

In the Unraid webGUI:

1. Go to **Plugins → Install Plugin**.
2. Paste the raw URL of the `.plg` file:

   ```
   https://raw.githubusercontent.com/nixta1/uv-unraid/main/plugins/uv.plg
   ```

3. Click **Install**. After the install script finishes, open a terminal and run
   `uv --version` to verify, or navigate to **Settings → Other Settings → uv**.

## Repository layout

```
uv-unraid/
├── plugins/
│   └── uv.plg                     # Generated plugin manifest (build output)
├── source/                        # Canonical, human-editable source tree
│   └── usr/local/emhttp/plugins/uv/
│       ├── uv.page                # Settings page (Menu="OtherSettings", Type=php)
│       ├── README.md              # Description shown in the Plugin Manager
│       ├── include/
│       │   ├── helpers.php        # PHP helpers used by uv.page
│       │   └── update.php         # CSRF-protected AJAX endpoint for "Update now"
│       └── scripts/
│           ├── install_uv.sh      # Downloads/updates the uv binary (idempotent)
│           └── remove_uv.sh       # Tolerant cleanup on plugin uninstall
├── scripts/
│   └── build-plg.sh               # Regenerates plugins/uv.plg from source/
├── .github/workflows/
│   └── validate.yml               # CI: xmllint + shellcheck + php -l + drift check
├── CHANGELOG.md
├── LICENSE
└── README.md
```

The files under `source/` are the canonical, editable copies of everything that ships
inside the plugin. `scripts/build-plg.sh` regenerates `plugins/uv.plg` by embedding each
file under `source/usr/local/emhttp/plugins/uv/` as a
`<FILE Name="…" Run="/bin/true"><INLINE>…</INLINE></FILE>` block, XML-escaping the
source bytes so they roundtrip cleanly through the plugin manager's XML parser. A
roundtrip verification step inside `build-plg.sh` parses the generated `.plg`, extracts
each inlined block and byte-compares it against its corresponding source file — any
drift aborts the build, and CI additionally re-runs the build to catch uncommitted
edits to either side.

Key format decisions (see comments in `scripts/build-plg.sh` for rationale):

- **No `<![CDATA[…]]>` wrappers.** DOCTYPE entity references (`&name;`, `&emhttpLOC;`,
  …) are not expanded inside CDATA, which would be a silent trap for future edits that
  try to use them. The build XML-escapes `&`, `<`, `>` instead; the plugin manager
  decodes them back to the original bytes before writing each file to disk.
- **Every `<FILE Name="…">` block carries `Run="/bin/true"`** as a defensive no-op.
  The format docs at plugin-docs.mstrhakr.com only show `Name=` paired with a `Run=`
  command; `/bin/true` guarantees both the "write file" and the "execute" code paths
  fire, regardless of whether `Name` alone would have been enough.
- **The `<CHANGES>` block is generated from `CHANGELOG.md`** so there is exactly one
  source of truth for the version history.

## How it interacts with Unraid's USB boot flash

Unraid boots from a read-only flash drive and extracts its root filesystem into RAM on
every boot. That means anything placed under `/` is wiped at shutdown. Plugins solve
this by:

1. Storing persistent state under `/boot/config/plugins/<name>/` on the USB stick.
2. Being re-installed on every boot — Unraid's init scripts re-run every `.plg` file
   that lives in `/boot/config/plugins/`.

This plugin follows that pattern: the `uv` binary is cached at
`/boot/config/plugins/uv/bin/uv`, and on each boot the `.plg` copies it back to
`/usr/local/bin/uv` without needing network access. The binary is only re-downloaded
from GitHub when the user explicitly requests an update (or when the cache is empty).

## Development

- Edit `source/…` and keep the matching `<INLINE>` block in `plugins/uv.plg` in sync.
- Bump the `version` entity in `plugins/uv.plg` (format `YYYY.MM.DD`) on every change.
- Add an entry at the top of `CHANGELOG.md` and of the `<CHANGES>` block in `uv.plg`.
- Push to `main` — Unraid pulls the `.plg` directly from `raw.githubusercontent.com`.

## License

MIT — see [LICENSE](LICENSE).

`uv` itself is (c) Astral Software Inc., licensed under Apache-2.0 / MIT. This plugin
only installs the upstream binary and is not affiliated with Astral or Unraid.
