const http = require('http');

function lvsAuthorize(userId, kind = 'user') {
  return new Promise((resolve) => {
    const body = JSON.stringify({ external_user_id: String(userId), kind });
    const req = http.request(
      {
        host: '127.0.0.1',
        port: 8788,
        path: '/authorize',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
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
