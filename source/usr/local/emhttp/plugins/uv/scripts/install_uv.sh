#!/bin/bash
#
# install_uv.sh — download and install Astral's `uv` binary on Unraid.
#
# This script is idempotent. It is invoked:
#   1. From the .plg file during plugin installation.
#   2. On every Unraid boot, because Unraid re-runs installed .plg files from
#      /boot/config/plugins/ as part of its init sequence.
#   3. Manually from the Settings page "Update now" button.
#
# Layout on disk:
#   /boot/config/plugins/uv/            — persistent state on the USB flash
#   /boot/config/plugins/uv/bin/uv      — cached binary (survives reboots)
#   /boot/config/plugins/uv/bin/uvx     — cached companion binary
#   /boot/config/plugins/uv/version     — cached version string (e.g. 0.5.11)
#   /usr/local/bin/uv                   — live symlink/copy (lost on reboot)
#
# Usage:
#   install_uv.sh                 # install cached, or fetch latest if no cache
#   install_uv.sh --update        # always fetch the latest release
#   install_uv.sh --version 0.5.0 # install a specific version

set -euo pipefail

PLUGIN=uv
CACHE_DIR=/boot/config/plugins/${PLUGIN}
BIN_CACHE=${CACHE_DIR}/bin
VERSION_FILE=${CACHE_DIR}/version
TARGET_DIR=/usr/local/bin
ARCH_TARBALL=uv-x86_64-unknown-linux-gnu.tar.gz
RELEASES_API=https://api.github.com/repos/astral-sh/uv/releases/latest
RELEASES_DL=https://github.com/astral-sh/uv/releases/download

mkdir -p "${BIN_CACHE}"

log()  { printf '[uv] %s\n' "$*"; }
err()  { printf '[uv] error: %s\n' "$*" >&2; }

FORCE_UPDATE=0
WANTED_VERSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --update)  FORCE_UPDATE=1; shift ;;
    --version) WANTED_VERSION=${2:?missing version}; shift 2 ;;
    --help|-h)
      sed -n '2,30p' "$0"; exit 0 ;;
    *)
      err "unknown argument: $1"; exit 2 ;;
  esac
done

resolve_latest_version() {
  # Returns the latest release tag (without a leading 'v') or empty on failure.
  local tag
  tag=$(curl -fsSL --max-time 15 "${RELEASES_API}" 2>/dev/null \
          | grep -Po '"tag_name"\s*:\s*"\K[^"]+' || true)
  echo "${tag#v}"
}

install_from_cache() {
  if [[ -x ${BIN_CACHE}/uv ]]; then
    install -m 0755 "${BIN_CACHE}/uv"  "${TARGET_DIR}/uv"
    [[ -x ${BIN_CACHE}/uvx ]] && install -m 0755 "${BIN_CACHE}/uvx" "${TARGET_DIR}/uvx"
    local v="unknown"
    [[ -f ${VERSION_FILE} ]] && v=$(<"${VERSION_FILE}")
    log "restored cached uv ${v} -> ${TARGET_DIR}/uv"
    return 0
  fi
  return 1
}

download_and_cache() {
  local version=$1
  local url="${RELEASES_DL}/${version}/${ARCH_TARBALL}"
  local tmp
  tmp=$(mktemp -d) || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" RETURN

  log "downloading ${url}"
  if ! curl -fsSL --max-time 120 -o "${tmp}/${ARCH_TARBALL}" "${url}"; then
    err "download failed"
    return 1
  fi

  if ! tar -xzf "${tmp}/${ARCH_TARBALL}" -C "${tmp}"; then
    err "extraction failed"
    return 1
  fi

  local src_uv src_uvx
  src_uv=$(find "${tmp}" -type f -name uv  | head -n1)
  src_uvx=$(find "${tmp}" -type f -name uvx | head -n1)

  if [[ -z ${src_uv} ]]; then
    err "uv binary not found inside tarball"
    return 1
  fi

  install -m 0755 "${src_uv}"  "${BIN_CACHE}/uv"
  install -m 0755 "${src_uv}"  "${TARGET_DIR}/uv"
  if [[ -n ${src_uvx} ]]; then
    install -m 0755 "${src_uvx}" "${BIN_CACHE}/uvx"
    install -m 0755 "${src_uvx}" "${TARGET_DIR}/uvx"
  fi

  printf '%s\n' "${version}" > "${VERSION_FILE}"
  log "installed uv ${version}"
}

# ---- main -----------------------------------------------------------------

if [[ ${FORCE_UPDATE} -eq 0 && -z ${WANTED_VERSION} ]]; then
  # Normal boot path: prefer the cache, no network round-trip.
  if install_from_cache; then
    exit 0
  fi
fi

# We need to hit the network.
if [[ -z ${WANTED_VERSION} ]]; then
  log "resolving latest uv release..."
  WANTED_VERSION=$(resolve_latest_version)
fi

if [[ -z ${WANTED_VERSION} ]]; then
  err "could not resolve a uv version to install"
  # Last-ditch fallback: restore whatever is cached.
  install_from_cache || exit 1
  exit 0
fi

if download_and_cache "${WANTED_VERSION}"; then
  exit 0
fi

err "download failed; falling back to cached binary"
install_from_cache || exit 1
