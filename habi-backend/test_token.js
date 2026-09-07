const http = require('http');

const data = JSON.stringify({ roomName: 'habi-voice-room', identity: 'godot-test', name: 'Godot Test' });

const opts = {
  hostname: 'localhost',
  port: 5000,
  path: '/api/livekit/token',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(data)
  }
};

const req = http.request(opts, (res) => {
  console.log('STATUS', res.statusCode);
  let body = '';
  res.setEncoding('utf8');
  res.on('data', (chunk) => body += chunk);
  res.on('end', () => {
    console.log('BODY', body);
  });
});

req.on('error', (e) => {
  console.error('Request error', e.message);
});

req.write(data);
req.end();
