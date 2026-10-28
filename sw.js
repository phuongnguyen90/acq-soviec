// Service worker: mở được khi mất mạng, và báo khi có bản mới.
const VERSION = '202610280943';
const CACHE = 'soviec-' + VERSION;
const ASSETS = ['./', './index.html', './config.js', './manifest.json', './icon.svg', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS))); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('message', e => { if (e.data === 'SKIP_WAITING') self.skipWaiting(); });
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  e.respondWith(fetch(e.request, { cache: 'no-cache' }).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; }).catch(() => caches.match(e.request).then(r => r || caches.match('./index.html'))));
});

self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: 'Thông báo', body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'ACQ Sổ việc', { body: d.body || '', icon: './icon-192.png', badge: './icon-192.png', tag: d.id || undefined, data: { job_id: d.job_id || null }, vibrate: [100, 50, 100] }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
    const url = new URL('./index.html#viec', self.registration.scope).href;
    for (const c of cs) { if ('focus' in c) { c.focus(); c.postMessage({ openJob: e.notification.data && e.notification.data.job_id }); return; } }
    return self.clients.openWindow(url);
  }));
});
