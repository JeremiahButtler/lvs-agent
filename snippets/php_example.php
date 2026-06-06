<?php
// LVS Agent integration — authorize a user before granting access
// Agent installation: curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main/install.sh | sudo bash

// Set LVS_LOCAL_TOKEN in your server environment (from /opt/lvs-agent/config.json)
define('LVS_LOCAL_TOKEN', getenv('LVS_LOCAL_TOKEN') ?: '');

function lvs_authorize(string $user_id, string $kind = 'user'): bool {
    $headers = ['Content-Type: application/json'];
    if (LVS_LOCAL_TOKEN !== '') {
        $headers[] = 'Authorization: Bearer ' . LVS_LOCAL_TOKEN;
    }
    $ch = curl_init('http://127.0.0.1:8788/authorize');
    curl_setopt_array($ch, [
        CURLOPT_POST          => true,
        CURLOPT_POSTFIELDS    => json_encode(['external_user_id' => $user_id, 'kind' => $kind]),
        CURLOPT_HTTPHEADER    => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT       => 2,
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
