# Changelog

All notable changes to the `uv-unraid` plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adopts Unraid's conventional `YYYY.MM.DD` version scheme.

## [2026.04.15] - 2026-04-15

### Added
- Initial release.
- Downloads and installs `uv` + `uvx` from the Astral GitHub releases.
- Caches the binary on `/boot/config/plugins/uv/bin/` so the plugin survives
  reboots without needing network access.
- Settings page under **Settings → User Utilities → uv** showing the installed
  version, cached version, binary path, and an "Update now" action.
- Clean uninstall script that removes the binary, cache directory and webGUI
  files.
