<?PHP
/*
 * Copyright 2026, uv-unraid contributors
 *
 * PHP helpers used by the uv settings page. Kept intentionally small — the
 * plugin has no configurable settings, just a status display and an
 * "Update now" action.
 */

function uv_binary_path(): string {
    return '/usr/local/bin/uv';
}

function uv_cache_dir(): string {
    return '/boot/config/plugins/uv';
}

function uv_installed_version(): ?string {
    $bin = uv_binary_path();
    if (!is_executable($bin)) {
        return null;
    }
    $out = @shell_exec(escapeshellarg($bin) . ' --version 2>/dev/null');
    if ($out === null || $out === false) {
        return null;
    }
    // `uv 0.5.11 (abc1234 2025-01-01)` → `0.5.11`
    $out = trim($out);
    if (preg_match('/^uv\s+(\S+)/', $out, $m)) {
        return $m[1];
    }
    return $out !== '' ? $out : null;
}

function uv_cached_version(): ?string {
    $f = uv_cache_dir() . '/version';
    if (!is_readable($f)) {
        return null;
    }
    $v = trim((string) @file_get_contents($f));
    return $v !== '' ? $v : null;
}

function uv_cached_binary_exists(): bool {
    return is_file(uv_cache_dir() . '/bin/uv');
}
