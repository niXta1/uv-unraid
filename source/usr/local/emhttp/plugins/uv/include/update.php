<?PHP
/*
 * Copyright 2026, uv-unraid contributors
 *
 * Endpoint hit by the "Update now" button on the uv settings page.
 * Validates the Unraid CSRF token, then runs install_uv.sh --update and
 * streams the combined stdout/stderr back to the caller.
 */

header('Content-Type: text/plain; charset=utf-8');

// Only accept POST — the endpoint has side effects (downloads + installs),
// so it must not be reachable via a link or img src.
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    echo "method not allowed\n";
    exit;
}

// -- CSRF -------------------------------------------------------------------
//
// Unraid stores the per-session CSRF token in /var/local/emhttp/var.ini as
// csrf_token=<hex>. Every write-effecting plugin endpoint is expected to
// compare the caller-supplied token against that value. hash_equals avoids
// timing side-channels.
$var      = @parse_ini_file('/var/local/emhttp/var.ini');
$expected = is_array($var) ? (string)($var['csrf_token'] ?? '') : '';
$received = (string)($_POST['csrf_token'] ?? '');

if ($expected === '' || !hash_equals($expected, $received)) {
    http_response_code(403);
    echo "CSRF token invalid\n";
    exit;
}

// -- Run the installer ------------------------------------------------------
$script = '/usr/local/emhttp/plugins/uv/scripts/install_uv.sh';

if (!is_executable($script)) {
    http_response_code(500);
    echo "install script not found or not executable: $script\n";
    exit;
}

// Redirect stderr into stdout so the streamed log is interleaved.
$descriptors = [
    1 => ['pipe', 'w'],
    2 => ['redirect', 1],
];
$proc = proc_open([$script, '--update'], $descriptors, $pipes);
if (!is_resource($proc)) {
    http_response_code(500);
    echo "failed to launch install script\n";
    exit;
}

while (!feof($pipes[1])) {
    $line = fgets($pipes[1]);
    if ($line === false) {
        break;
    }
    echo $line;
    @ob_flush();
    @flush();
}

fclose($pipes[1]);
$status = proc_close($proc);
echo "\n[exit $status]\n";
