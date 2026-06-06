<?php
// LVS Agent integration — authorize a user before granting access
// Agent must be running: curl -sSL https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main/install.sh | sudo bash

function lvs_authorize(string $user_id, string $kind = 'user'): bool {
    $ch = curl_init('http://127.0.0.1:8788/authorize');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode(['external_user_id' => $user_id, 'kind' => $kind]),
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 2,
    ]);
    $body = curl_exec($ch);
    curl_close($ch);
    if ($body === false) return false; // agent unreachable — fail closed
    $data = json_decode($body, true);
    return ($data['status'] ?? '') === 'granted';
}

// Usage: call before showing licensed features
if (!lvs_authorize((string) $current_user_id)) {
    // show notice: license limit reached or agent unavailable
}
