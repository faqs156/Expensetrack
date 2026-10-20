/* ExpenseTrack offline service worker.
 * Network-first for app code so deploys are not stuck on an old banner/build.
 * Bump CACHE_NAME on every release that must reach users immediately.
 */
'use strict';

const CACHE_NAME = 'expensetrack-shell-v4';

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
        './icons/Icon-192.png',
        './icons/Icon-512.png',
        './icons/apple-touch-icon.png',
      ]).catch((err) => {
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
  if (url.origin !== self.location.origin) return;

  // App JS/WASM must not stick on an old deploy (stale banner / auth bugs).
  const path = url.pathname;
  if (
    path.endsWith('.js') ||
    path.endsWith('.mjs') ||
    path.endsWith('.wasm') ||
    path.includes('main.dart.js') ||
    path.includes('flutter_bootstrap')
  ) {
    event.respondWith(networkOnlyThenCache(event.request));
    return;
  }

  event.respondWith(networkFirstThenCache(event.request));
});

async function networkOnlyThenCache(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const fresh = await fetch(request, { cache: 'no-cache' });
    if (fresh && fresh.ok) {
      cache.put(request, fresh.clone());
    }
    return fresh;
  } catch (_) {
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    return Response.error();
  }
}

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
    if (request.mode === 'navigate') {
      const shell = await cache.match('./index.html');
      if (shell) return shell;
    }
    return Response.error();
  }
}
