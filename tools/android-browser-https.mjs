// Development-only loopback TLS gateway. Uses Node built-ins, no extra packages.
// Android's localhost:5173 is reversed to this listener; Host/Origin/cookies stay
// localhost:5173, so the existing API origin and CSRF checks remain unchanged.
import https from 'node:https'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { X509Certificate } from 'node:crypto'

const directory = path.join(process.env.LOCALAPPDATA, 'SmartNutrition', 'browser-https')
if (process.argv[2] === '--check') {
  const request = https.get('https://localhost:5174/giris', {
    family: 4, ca: new X509Certificate(readFileSync(path.join(directory, 'root-ca.crt'))).toString(),
    rejectUnauthorized: true, timeout: 5000,
  }, response => {
    response.resume()
    response.on('end', () => { process.exitCode = response.statusCode === 200 ? 0 : 1 })
  })
  request.on('timeout', () => request.destroy(new Error('Timeout')))
  request.on('error', error => { console.error(`Android HTTPS check failed: ${error.code ?? 'connection error'}`); process.exitCode = 1 })
} else {
  const upstreamCa = readFileSync(process.env.SMART_NUTRITION_HTTPS_CERT)
  const server = https.createServer({
    cert: readFileSync(path.join(directory, 'localhost.pem')),
    key: readFileSync(path.join(directory, 'localhost.key')),
    minVersion: 'TLSv1.2',
  })
  function forward(request) {
    return https.request({
      hostname: '127.0.0.1', port: 5173, servername: 'localhost',
      ca: upstreamCa, rejectUnauthorized: true,
      method: request.method, path: request.url, headers: request.headers,
    })
  }
  server.on('request', (request, response) => {
    const upstream = forward(request)
    upstream.on('response', result => {
      response.writeHead(result.statusCode, result.headers)
      result.on('error', () => response.destroy())
      result.pipe(response)
    })
    upstream.on('error', () => {
      if (!response.headersSent) response.writeHead(502)
      response.end('Local HTTPS upstream unavailable.')
    })
    request.on('error', () => upstream.destroy())
    response.on('close', () => upstream.destroy())
    request.pipe(upstream)
  })
  // Forward the Vite HMR handshake without disabling its websocket token checks.
  server.on('upgrade', (request, socket, head) => {
    const upstream = forward(request)
    upstream.on('upgrade', (response, peer, upstreamHead) => {
      const headers = response.rawHeaders.reduce((lines, value, index, all) =>
        index % 2 === 0 ? [...lines, `${value}: ${all[index + 1]}`] : lines, [])
      socket.write(`HTTP/1.1 101 Switching Protocols\r\n${headers.join('\r\n')}\r\n\r\n`)
      if (head.length) peer.write(head)
      if (upstreamHead.length) socket.write(upstreamHead)
      socket.on('error', () => peer.destroy())
      peer.on('error', () => socket.destroy())
      socket.on('close', () => peer.destroy())
      peer.on('close', () => socket.destroy())
      socket.pipe(peer).pipe(socket)
    })
    upstream.on('response', response => { response.resume(); socket.destroy() })
    upstream.on('error', () => socket.destroy())
    socket.on('error', () => upstream.destroy())
    upstream.end()
  })
  server.on('error', () => { console.error('Android HTTPS listener failed.'); process.exitCode = 1 })
  server.listen(5174, '127.0.0.1', () => console.log('Android HTTPS ready on loopback port 5174.'))
}
