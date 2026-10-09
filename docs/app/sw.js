// Service worker existuje jen proto, aby byl web instalovatelný jako PWA —
// bez toho ho Chrome na Androidu nenabídne v systémovém sdílení. Nic necachuje.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => e.respondWith(fetch(e.request)));
