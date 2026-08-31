// Cache-first asset serving for the web client, so the ~300 MB asset tree crosses the network
// once per deploy rather than being at the mercy of whatever cache headers the host happens to
// send. Registered by loader.html; the cache name is stamped per deploy by build-web.sh
// (95f9536 below), so a new deploy starts a fresh cache and activation sweeps the old
// ones — which is the only invalidation this needs, because game assets are not content-hashed
// (bevy fetches them by their stable paths) and would otherwise be cache-first stale for ever.
//
// Two deliberate choices:
//
// - CACHE ON FIRST FETCH, never precache. Pulling the whole tree up front would front-load the
//   exact grind this exists to avoid; the cache fills the way the VRAM banks do, with what has
//   actually flown past.
// - NAVIGATIONS GO NETWORK-FIRST (falling back to cache when offline), so a fresh deploy's
//   loader and bundle pages show up on the next visit rather than after a cache generation.
//   Everything else — glbs, wasm, js, audio — is immutable within a deploy and served
//   cache-first.
//
// The browser revalidates this script itself on navigation regardless of HTTP caching (the
// spec's own rule for service workers), which is what lets the stamp below take effect.

const CACHE = 'psw-95f9536';

self.addEventListener('install', (event) => {
  // No precache; take over from any previous worker without waiting for its pages to close.
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // A new deploy is a new cache; sweep every generation but this one.
      for (const name of await caches.keys()) {
        if (name.startsWith('psw-') && name !== CACHE) {
          await caches.delete(name);
        }
      }
      // Control already-open pages too, so a first visit's later fetches are cached.
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  // Only plain same-origin GETs. Cross-origin, POSTs and the WebSocket (not a fetch at all)
  // pass straight through untouched.
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) {
    return;
  }

  if (req.mode === 'navigate') {
    // Pages: the network's word first, the cache only when there is no network.
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(req);
          if (fresh.ok) {
            const cache = await caches.open(CACHE);
            cache.put(req, fresh.clone());
          }
          return fresh;
        } catch (_) {
          const held = await caches.match(req);
          if (held) return held;
          throw _;
        }
      })()
    );
    return;
  }

  // Everything else: cache-first. Only complete 200s are kept — a partial (206, range-requested
  // audio) or opaque response stored here would be replayed wrong for ever.
  event.respondWith(
    (async () => {
      const held = await caches.match(req);
      if (held) return held;
      const fresh = await fetch(req);
      if (fresh.ok && fresh.status === 200 && fresh.type === 'basic') {
        const cache = await caches.open(CACHE);
        cache.put(req, fresh.clone());
      }
      return fresh;
    })()
  );
});
