<?PHP
/*
 * Copyright 2026, uv-unraid contributors
 *
 * Endpoint hit by the "Update now" button on the uv settings page.
 * Runs the install script with --update and streams the output back.
 */

header('Content-Type: text/plain; charset=utf-8');

$script = '/usr/local/emhttp/plugins/uv/scripts/install_uv.sh';

if (!is_executable($script)) {
    http_response_code(500);
    echo "install script not found or not executable: $script\n";
    exit;
}

// Run the installer with --update and capture combined stdout/stderr.
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
    echo fgets($pipes[1]);
    @ob_flush();
    @flush();
}

fclose($pipes[1]);
$status = proc_close($proc);
echo "\n[exit $status]\n";
