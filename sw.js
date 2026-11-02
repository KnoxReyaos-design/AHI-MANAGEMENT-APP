const CACHE='ahi-shell-v12';
const SHELL=['./','index.html','manifest.json','icon-192.png','icon-512.png','logo.jpg'];
// Version-pinned library the app imports at startup. Cached so the shell can start offline.
const LIB='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.57.0/+esm';
self.addEventListener('install',event=>{
  event.waitUntil((async()=>{
    const cache=await caches.open(CACHE);
    await cache.addAll(SHELL);
    // Best effort: a failure here must not block installation of the shell itself.
    try{await cache.add(new Request(LIB,{mode:'cors'}))}catch(_){}
    await self.skipWaiting();
  })());
});
self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
  const request=event.request;
  const url=new URL(request.url);
  if(request.method!=='GET') return;
  // Never intercept Supabase auth, database, storage, or function traffic.
  if(url.hostname.endsWith('supabase.co')) return;
  if(request.mode==='navigate'){
    event.respondWith(fetch(request,{cache:'no-store'}).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put('./',copy))}
      return response;
    }).catch(()=>caches.match('./').then(cached=>cached||caches.match('index.html'))));
    return;
  }
  const isLib=url.hostname==='cdn.jsdelivr.net'&&url.href===LIB;
  if(url.origin===self.location.origin||isLib){
    event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy))}
      return response;
    })));
  }
});
