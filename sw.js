/**
 * Bill Splitter - Service Worker
 * Version: 1.0.0
 * Features: Offline caching, Stale-While-Revalidate, Dynamic asset caching, Font/CDN caching
 */

const CACHE_NAME = 'bill-splitter-v1.0.0';

// Critical core assets for offline operation
const PRECACHE_ASSETS = [
    './',
    './index.html',
    './style.css?v=2.2',
    './style.css',
    './script.js?v=2.2',
    './script.js',
    './manifest.json',
    './favicon.ico',
    './icons/favicon-16x16.png',
    './icons/favicon-32x32.png',
    './icons/icon-72x72.png',
    './icons/icon-96x96.png',
    './icons/icon-128x128.png',
    './icons/icon-144x144.png',
    './icons/icon-152x152.png',
    './icons/apple-touch-icon.png',
    './icons/icon-192x192.png',
    './icons/icon-384x384.png',
    './icons/icon-512x512.png',
    './icons/icon-maskable-192.png',
    './icons/icon-maskable-512.png',
    './icons/icon.svg',
    './icons/icon-maskable.svg'
];

// External CDNs to cache dynamically
const CACHABLE_ORIGINS = [
    'fonts.googleapis.com',
    'fonts.gstatic.com',
    'cdn.jsdelivr.net'
];

// Install Event: Pre-cache static assets
self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            return cache.addAll(PRECACHE_ASSETS).catch((err) => {
                console.warn('[SW] Some precache assets failed to load:', err);
            });
        }).then(() => self.skipWaiting())
    );
});

// Activate Event: Clean up outdated caches and take control immediately
self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) => {
            return Promise.all(
                keys.map((key) => {
                    if (key !== CACHE_NAME) {
                        console.log('[SW] Removing old cache:', key);
                        return caches.delete(key);
                    }
                })
            );
        }).then(() => self.clients.claim())
    );
});

// Message Event: Allow web page to trigger skipWaiting
self.addEventListener('message', (event) => {
    if (event.data && event.data.type === 'SKIP_WAITING') {
        self.skipWaiting();
    }
});

// Fetch Event: Cache strategies
self.addEventListener('fetch', (event) => {
    const request = event.request;
    const url = new URL(request.url);

    // Only handle GET requests
    if (request.method !== 'GET') {
        return;
    }

    // Bypass Chrome Extension requests & unsupported schemes
    if (!url.protocol.startsWith('http')) {
        return;
    }

    // Supabase API requests: Network first (bypass SW caching for real-time cloud data)
    if (url.hostname.includes('supabase.co')) {
        event.respondWith(
            fetch(request).catch(() => {
                return new Response(
                    JSON.stringify({ offline: true, error: 'Network unavailable. Running in offline mode.' }),
                    {
                        headers: { 'Content-Type': 'application/json' },
                        status: 503,
                        statusText: 'Service Unavailable (Offline)'
                    }
                );
            })
        );
        return;
    }

    // HTML Navigation requests (pages): Network first with cache fallback
    if (request.mode === 'navigate') {
        event.respondWith(
            fetch(request)
                .then((networkResponse) => {
                    if (networkResponse && networkResponse.status === 200) {
                        const copy = networkResponse.clone();
                        caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
                    }
                    return networkResponse;
                })
                .catch(async () => {
                    const cachedResponse = await caches.match(request);
                    if (cachedResponse) return cachedResponse;
                    return caches.match('./index.html') || caches.match('/');
                })
        );
        return;
    }

    // External Fonts & CDN Scripts: Cache-First with Network fallback
    if (CACHABLE_ORIGINS.some((origin) => url.hostname.includes(origin))) {
        event.respondWith(
            caches.match(request).then((cachedResponse) => {
                if (cachedResponse) return cachedResponse;
                return fetch(request).then((networkResponse) => {
                    if (networkResponse && networkResponse.status === 200) {
                        const copy = networkResponse.clone();
                        caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
                    }
                    return networkResponse;
                }).catch(() => null);
            })
        );
        return;
    }

    // Local Static Assets (CSS, JS, Images, Icons, Manifest): Stale-While-Revalidate
    event.respondWith(
        caches.match(request).then((cachedResponse) => {
            const fetchPromise = fetch(request)
                .then((networkResponse) => {
                    if (networkResponse && networkResponse.status === 200) {
                        const copy = networkResponse.clone();
                        caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
                    }
                    return networkResponse;
                })
                .catch(() => cachedResponse);

            return cachedResponse || fetchPromise;
        })
    );
});
