/* AHI v41 app-shell service worker.
   - Financial/API (cross-origin) requests are never cached, queued or touched.
   - Update model: any byte change in this file installs a new worker, which precaches fresh copies
     (bypassing the HTTP cache), takes over at once, and deletes every older ahi-client-* cache.
   - index.html is also fingerprinted (SHA-256) so the page can tell when a newer index.html is live
     even if this file was not changed. */
const VERSION = 'v41';
const CACHE_NAME = 'ahi-client-' + VERSION;
const CACHE_PREFIX = 'ahi-client-';
const INDEX_URL = './index.html';
const HASH_HEADER = 'x-ahi-hash';
const NAV_TIMEOUT_MS = 5000;     /* with a cached copy, wait this long for the network before using it */
const CHECK_TIMEOUT_MS = 10000;  /* page-requested freshness check */

/* Must be present for the install to succeed. */
const REQUIRED_ASSETS = ['./manifest.json'];
/* Best effort: a failure here must not block an update. */
const OPTIONAL_ASSETS = ['./icon-192.png', './icon-512.png'];
const RUNTIME_PATHS = new Set(['manifest.json', 'icon-192.png', 'icon-512.png']);

let pendingStore = Promise.resolve();

const toHex = buf => Array.from(new Uint8Array(buf), b => b.toString(16).padStart(2, '0')).join('');
async function sha256(buf) { return toHex(await crypto.subtle.digest('SHA-256', buf)); }
function withTimeout(promise, ms) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    promise.then(v => { clearTimeout(t); resolve(v); }, e => { clearTimeout(t); reject(e); });
  });
}

/* Store index.html together with its fingerprint. Headers are rebuilt so a stale
   Content-Encoding/Length from the network response can never corrupt the cached copy. */
async function storeHtml(cacheName, response) {
  const buf = await response.arrayBuffer();
  const hash = await sha256(buf);
  const make = () => new Response(buf.slice(0), {
    status: 200,
    headers: { 'content-type': 'text/html; charset=utf-8', [HASH_HEADER]: hash }
  });
  const cache = await caches.open(cacheName);
  await cache.put(INDEX_URL, make());
  await cache.put('./', make());
  return hash;
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    try {
      const cache = await caches.open(CACHE_NAME);
      /* cache:'reload' skips the HTTP cache (GitHub Pages sends max-age=600), so a new version
         never precaches a ten-minute-old copy of itself. */
      const fresh = url => fetch(new Request(url, { cache: 'reload' }));

      const html = await fresh(INDEX_URL);
      if (!html.ok) throw new Error('index.html ' + html.status);
      await storeHtml(CACHE_NAME, html);

      for (const url of REQUIRED_ASSETS) {
        const r = await fresh(url);
        if (!r.ok) throw new Error(url + ' ' + r.status);
        await cache.put(url, r);
      }
      await Promise.all(OPTIONAL_ASSETS.map(async url => {
        try { const r = await fresh(url); if (r.ok) await cache.put(url, r); } catch (_) { /* tolerated */ }
      }));
    } catch (err) {
      /* Incomplete download: discard the half-built cache and fail the install.
         The current worker and its cache keep running untouched; the browser retries on the next check. */
      await caches.delete(CACHE_NAME);
      throw err;
    }
    /* Only reached when everything required is cached, so the new worker is complete before it takes over. */
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k.startsWith(CACHE_PREFIX) && k !== CACHE_NAME).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('message', event => {
  const data = event.data || {};
  const port = event.ports && event.ports[0];
  const reply = msg => { try { port ? port.postMessage(msg) : event.source && event.source.postMessage(msg); } catch (_) {} };

  if (data.type === 'SKIP_WAITING') { self.skipWaiting(); return; }

  if (data.type === 'GET_VERSION') { reply({ version: VERSION, cache: CACHE_NAME }); return; }

  /* Fingerprint of the index.html this worker last served (or has cached). */
  if (data.type === 'GET_SERVED_HASH') {
    event.waitUntil((async () => {
      try {
        await pendingStore.catch(() => {});
        const cache = await caches.open(CACHE_NAME);
        const hit = await cache.match(INDEX_URL);
        reply({ hash: hit ? hit.headers.get(HASH_HEADER) : null });
      } catch (_) { reply({ hash: null }); }
    })());
    return;
  }

  /* Fingerprint of the index.html that is live on the server right now. */
  if (data.type === 'CHECK_HTML') {
    event.waitUntil((async () => {
      try {
        const ctl = new AbortController();
        const t = setTimeout(() => ctl.abort(), CHECK_TIMEOUT_MS);
        const r = await fetch(new Request(INDEX_URL, { cache: 'no-store', signal: ctl.signal }));
        clearTimeout(t);
        if (!r.ok) { reply({ ok: false }); return; }
        reply({ ok: true, hash: await sha256(await r.arrayBuffer()) });
      } catch (_) { reply({ ok: false }); }
    })());
  }
});

async function handleNavigate(event) {
  const request = event.request;
  const cache = await caches.open(CACHE_NAME);
  const cached = (await cache.match(INDEX_URL)) || (await caches.match(INDEX_URL));

  /* no-cache = always revalidate with the server (cheap 304 when unchanged). */
  const network = fetch(request.url, { cache: 'no-cache', credentials: 'same-origin' });
  network.catch(() => {});

  try {
    const resp = cached
      ? await Promise.race([network, new Promise((_, rej) => setTimeout(() => rej(new Error('slow')), NAV_TIMEOUT_MS))])
      : await network;
    if (resp && resp.ok) {
      /* The cached copy and its fingerprint always describe the HTML this page was actually given.
         (Still inside respondWith, so waitUntil is valid and keeps the worker alive.) */
      pendingStore = storeHtml(CACHE_NAME, resp.clone()).catch(() => {});
      event.waitUntil(pendingStore);
      return resp;
    }
    return cached || resp;                     /* server error: prefer a good cached copy */
  } catch (_) {
    return cached || Response.error();         /* offline or too slow: the page's update check will catch up later */
  }
}

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(handleNavigate(event));
    return;
  }

  const file = url.pathname.split('/').pop();
  if (!RUNTIME_PATHS.has(file)) return;        /* sw.js itself and everything else go straight to the network */

  /* Static brand assets: serve cached copy instantly, revalidate in the background. */
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request, { ignoreSearch: true });
    const refresh = fetch(request, { cache: 'no-cache' }).then(async resp => {
      if (resp && resp.ok) await cache.put(request, resp.clone());
      return resp;
    }).catch(() => cached);
    if (cached) { event.waitUntil(refresh); return cached; }
    return (await refresh) || Response.error();
  })());
});
