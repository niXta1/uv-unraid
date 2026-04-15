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
- Settings page under **Settings → User Utilities → uv** showing the installed version,
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
   `uv --version` to verify, or navigate to **Settings → uv**.

## Repository layout

```
uv-unraid/
├── plugins/
│   └── uv.plg                     # The plugin manifest (single source of truth)
├── source/                        # Canonical, human-editable copies of files that
│   └── usr/local/emhttp/          # the .plg inlines into /usr/local/emhttp/plugins/uv/
│       └── plugins/uv/
│           ├── uv.page            # Settings page (Unraid webGUI)
│           ├── README.md          # Description shown in the Plugin Manager
│           ├── include/
│           │   └── helpers.php    # PHP helpers used by uv.page
│           └── scripts/
│               ├── install_uv.sh  # Downloads/updates the uv binary
│               └── remove_uv.sh   # Removes uv on plugin uninstall
├── .github/workflows/
│   └── validate.yml               # CI: XML lint + shellcheck
├── CHANGELOG.md
├── LICENSE
└── README.md
```

The files under `source/` are the canonical, editable copies of everything that ships
inside the plugin. The same content is embedded as `<FILE Name="...">…<INLINE>…</INLINE>`
blocks in `plugins/uv.plg`, which is what Unraid actually downloads and executes. If you
edit something under `source/`, remember to sync the corresponding block in `uv.plg`.
Both copies are checked by CI to catch drift.

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
