// Proxy CONNECT minimo con allowlist (ALLOW=host1,host2; vacio = permite todo) que registra cada destino.
import http from 'node:http';
import net from 'node:net';
const allow = (process.env.ALLOW ?? '').split(',').filter(Boolean);
const ok = (h) => allow.length === 0 || allow.some((a) => h === a || h.endsWith('.' + a));
http.createServer((req, res) => { console.log(`HTTP ${req.method} ${req.headers.host} ${ok(req.headers.host?.split(':')[0]) ? 'ALLOW' : 'DENY'}`); res.writeHead(405); res.end(); })
  .on('connect', (req, client, head) => {
    const [host, port] = req.url.split(':');
    const allowed = ok(host);
    console.log(`CONNECT ${host}:${port} ${allowed ? 'ALLOW' : 'DENY'}`);
    if (!allowed) { client.end('HTTP/1.1 403 Forbidden\r\n\r\n'); return; }
    const up = net.connect(Number(port), host, () => { client.write('HTTP/1.1 200 OK\r\n\r\n'); up.write(head); up.pipe(client); client.pipe(up); });
    up.on('error', () => client.destroy()); client.on('error', () => up.destroy());
  }).listen(3128, () => console.log('proxy up allow=' + (allow.join(',') || '*')));
