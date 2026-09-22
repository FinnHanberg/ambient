/* ═══════════════════════════════════════════════════════════════════════════
   The studio's server: static files, plus one endpoint that can reach a model.

   The key is read here and never sent to the page. A browser holding an API key
   is a key in the DOM, in the devtools, and in every screenshot of the tool.

   Key, in order: $ANTHROPIC_API_KEY, then ~/.ambient/studio-key.
   With neither, /api/ask answers 503 and says so — the client then falls back
   to its local proposer rather than pretending.
   ═══════════════════════════════════════════════════════════════════════════ */
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

/* fileURLToPath, not .pathname: this tree lives under "Claude 1", and a
   percent-encoded space makes every static path miss. */
const ROOT = fileURLToPath(new URL('.', import.meta.url));
const PORT = +(process.env.PORT || 4491);

const KEY = (() => {
  if(process.env.ANTHROPIC_API_KEY) return process.env.ANTHROPIC_API_KEY.trim();
  const f = join(homedir(), '.ambient', 'studio-key');
  if(existsSync(f)) return readFileSync(f, 'utf8').trim();
  return null;
})();

const TYPES = { '.html':'text/html', '.js':'text/javascript', '.mjs':'text/javascript',
  '.css':'text/css', '.json':'application/json', '.png':'image/png', '.jpg':'image/jpeg',
  '.svg':'image/svg+xml', '.woff2':'font/woff2' };

const json = (res, code, body) => {
  const s = JSON.stringify(body);
  res.writeHead(code, { 'content-type':'application/json', 'content-length':Buffer.byteLength(s) });
  res.end(s);
};

async function ask(req, res){
  if(!KEY) return json(res, 503, { error:'no key',
    detail:'Set ANTHROPIC_API_KEY, or put a key in ~/.ambient/studio-key, then restart the server.' });

  let body = '';
  for await (const c of req) { body += c; if(body.length > 200_000) return json(res, 413, { error:'too large' }); }
  let ask;
  try { ask = JSON.parse(body); } catch { return json(res, 400, { error:'bad json' }); }

  try{
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method:'POST',
      headers:{ 'x-api-key':KEY, 'anthropic-version':'2023-06-01', 'content-type':'application/json' },
      body: JSON.stringify({
        model: ask.model || 'claude-sonnet-5',
        max_tokens: 2000,
        system: ask.system || '',
        messages: [{ role:'user', content: ask.prompt || '' }],
      }),
    });
    const data = await r.json();
    if(!r.ok) return json(res, r.status, { error:'api', detail:data?.error?.message || r.statusText });
    const text = (data.content || []).map(c => c.text || '').join('');
    json(res, 200, { text });
  } catch(e){
    json(res, 502, { error:'unreachable', detail:String(e.message || e) });
  }
}

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if(url.pathname === '/api/ask'){
    if(req.method !== 'POST') return json(res, 405, { error:'POST only' });
    return ask(req, res);
  }
  if(url.pathname === '/api/state') return json(res, 200, { model: !!KEY });

  let p = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, '');
  if(p.endsWith('/')) p += 'index.html';
  const file = join(ROOT, p);
  if(!file.startsWith(ROOT)) { res.writeHead(403); return res.end('no'); }
  try{
    const buf = await readFile(file);
    res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream',
                         'cache-control':'no-store' });
    res.end(buf);
  } catch { res.writeHead(404); res.end('not found'); }
}).listen(PORT, () => {
  console.log(`studio on http://localhost:${PORT}  ·  model ${KEY ? 'connected' : 'not connected'}`);
});
