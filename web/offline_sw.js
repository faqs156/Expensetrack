/* ExpenseTrack offline service worker.
 * Cache-as-you-go for same-origin GET requests (app shell, JS, WASM, icons).
 * Bump CACHE_NAME when you need to force clients off an old shell.
 * Does NOT cache cross-origin API calls (there are none).
 */
'use strict';

const CACHE_NAME = 'expensetrack-shell-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      cache.addAll([
        './',
        './index.html',
        './manifest.json',
        './favicon.png',
        './sqlite3.wasm',
        './sqflite_sw.js',
        './flutter_bootstrap.js',
        './icons/Icon-192.png',
        './icons/Icon-512.png',
        './icons/apple-touch-icon.png',
      ]).catch((err) => {
        // Precache best-effort; runtime caching still fills the rest.
        console.warn('ExpenseTrack SW precache partial failure', err);
      }),
    ),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((k) => k.startsWith('expensetrack-') && k !== CACHE_NAME)
          .map((k) => caches.delete(k)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) {
    // google_fonts etc. — network only; browser HTTP cache may still help
    return;
  }

  event.respondWith(networkFirstThenCache(event.request));
});

async function networkFirstThenCache(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const fresh = await fetch(request);
    if (fresh && fresh.ok) {
      cache.put(request, fresh.clone());
    }
    return fresh;
  } catch (_) {
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    // Offline navigation fallback
    if (request.mode === 'navigate') {
      const shell = await cache.match('./index.html');
      if (shell) return shell;
    }
    return Response.error();
  }
}
