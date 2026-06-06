const http = require('http');

// Set LVS_LOCAL_TOKEN in your environment (from /opt/lvs-agent/config.json)
const LVS_LOCAL_TOKEN = process.env.LVS_LOCAL_TOKEN || '';

function lvsAuthorize(userId, kind = 'user') {
  return new Promise((resolve) => {
    const body = JSON.stringify({ external_user_id: String(userId), kind });
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
    };
    if (LVS_LOCAL_TOKEN) {
      headers['Authorization'] = `Bearer ${LVS_LOCAL_TOKEN}`;
    }
    const req = http.request(
      {
        host: '127.0.0.1',
        port: 8788,
        path: '/authorize',
        method: 'POST',
        headers,
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          try { resolve(JSON.parse(data).status === 'granted'); }
          catch { resolve(false); }
        });
      }
    );
    req.setTimeout(2000, () => { req.destroy(); resolve(false); });
    req.on('error', () => resolve(false));
    req.write(body);
    req.end();
  });
}

// Usage
lvsAuthorize(userId).then((granted) => {
  if (!granted) {
    // license limit reached or agent unavailable
  }
});
