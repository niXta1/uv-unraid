# uv

Installs [uv](https://github.com/astral-sh/uv), Astral's extremely fast Python package
and project manager, into `/usr/local/bin` on Unraid.

The plugin downloads the official upstream binary from Astral's GitHub releases
(`uv-x86_64-unknown-linux-gnu.tar.gz`) on first install, caches it on the USB flash
drive at `/boot/config/plugins/uv/bin/`, and restores it to `/usr/local/bin/uv` and
`/usr/local/bin/uvx` on every boot — so no network access is required after the first
install.

## Usage

Open a terminal and run:

```
uv --version
uv python install 3.12
uv venv
```

A Settings page is available under **Settings → User Utilities → uv** where you can
see the installed version and trigger an update.

## Links

- Upstream project: <https://github.com/astral-sh/uv>
- Plugin source: <https://github.com/nixta1/uv-unraid>
