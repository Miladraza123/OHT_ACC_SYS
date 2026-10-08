/* ═══════════════════════════════════════════════════════════════
   Client Service Worker
   ZAROORI USOOL: Ye sirf STATIC files (HTML/manifest/icons) cache
   karta hai — kabhi bhi Supabase ya kisi API-call ko na cache karta
   hai, na "background" mein dobara bhejta hai. Har accounting-save
   hamesha seedha internet se, live jata hai — koi duplicate ka khatra
   nahi. Version badhane ke liye sirf CACHE_VERSION number badlein.
   ═══════════════════════════════════════════════════════════════ */

var CACHE_VERSION = 'oht-qtc-v14';

var SHELL_FILES = [
  './',
  './index.html',
  './client1-index.html',
  './client1-masters.html',
  './client1-billing.html',
  './client1-cutting.html',
  './client1-daily-ledger.html',
  './app-config.js',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
];

/* CDN ki libraries — in ke baghair offline safha khulta hi nahi (supabase-js har
   app ka pehla script hai). jsDelivr CORS deta hai, is liye "cors" mode se
   mangwa kar rakhte hain: opaque (status 0) jawab cache mein nahi rakhte. Pata
   bilkul wohi jo HTML ke <script src> mein hai. */
var CDN_FILES = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js'
];

/* Apni files ka cache-pata BINA "?..." ke. Shell iframes ko roz naya "?v=" deti
   hai aur khud "?probe=" mangwati hai — pehle har pata alag jagah cache hota
   (cache barhta rehta) aur agle din offline wala naya pata cache mein milta hi
   nahi tha (khali safha). */
function keyOf(url) {
  var u = new URL(url);
  return u.origin === self.location.origin ? u.origin + u.pathname : url;
}

function fill(cache) {
  // apni files lazmi (cache:'reload' — browser ka purana HTTP cache nahi)
  return cache.addAll(SHELL_FILES.map(function (f) { return new Request(f, { cache: 'reload' }); }))
    .then(function () {
      // CDN ki koshish — net na ho to install nahi rukta, baad mein istemaal par aa jati hai
      return Promise.all(CDN_FILES.map(function (u) {
        return fetch(u, { mode: 'cors', credentials: 'omit', cache: 'reload' }).then(function (res) {
          if (res && res.ok) return cache.put(u, res);
        }).catch(function () {});
      }));
    });
}

self.addEventListener('install', function (event) {
  event.waitUntil(caches.open(CACHE_VERSION).then(fill));
  // skipWaiting YAHAN NAHI. Pehle naya SW foran qabza kar leta tha aur shell
  // khud reload kar deti thi — banda bill likh raha hota aur draft urh jata.
  // Ab naya SW "waiting" mein rehta hai; shell banner dikhati hai, aur
  // "Update karein" dabane par hi SKIP_WAITING aata hai (neeche).
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(
        names.filter(function (n) { return n !== CACHE_VERSION; })
             .map(function (n) { return caches.delete(n); })
      );
    }).then(function () { return self.clients.claim(); })
  );
});

function putCopy(key, res) {
  if (!res || !res.ok || (res.type !== 'basic' && res.type !== 'cors')) return;
  var copy = res.clone();
  caches.open(CACHE_VERSION).then(function (cache) { cache.put(key, copy); });
}

self.addEventListener('fetch', function (event) {
  var url = event.request.url;

  // ZAROORI GUARD: koi bhi Supabase call, ya koi bhi GET-se-alag method
  // (POST/PUT/PATCH/DELETE) — seedha network se, kabhi cache se nahi,
  // kabhi bhi service-worker "background sync" ki koshish nahi karega.
  if (event.request.method !== 'GET') return;
  if (url.indexOf('supabase.co') !== -1) return;
  if (url.indexOf('/rest/v1/') !== -1 || url.indexOf('/auth/v1/') !== -1 || url.indexOf('/rpc/') !== -1) return;

  // CDN libraries: pehle cache (offline bhi chale), peeche se taaza kar lo
  if (CDN_FILES.indexOf(url) !== -1) {
    event.respondWith(
      caches.match(url).then(function (cached) {
        var net = fetch(url, { mode: 'cors', credentials: 'omit' }).then(function (res) {
          putCopy(url, res);
          return res;
        }).catch(function () { return cached; });
        return cached || net;
      })
    );
    return;
  }

  // Sirf apni hi site ki static files ke liye kuch karo
  if (url.indexOf(self.location.origin) !== 0) return;

  var key = keyOf(url);
  var isHtml = event.request.mode === 'navigate' || /\.html$|\/$/.test(key);

  if (isHtml) {
    // ZAROORI: HTML files (index/masters/billing/daily-ledger) ke liye
    // hamesha PEHLE INTERNET try karo — taake koi bhi naya deploy turant
    // milta rahe (bilkul jaisa Service Worker ke bina hota hai). Cache
    // sirf tab kaam aaye jab internet bilkul na ho.
    event.respondWith(
      fetch(event.request).then(function (res) {
        putCopy(key, res);
        return res;
      }).catch(function () {
        return caches.match(key).then(function (hit) {
          return hit || caches.match(event.request, { ignoreSearch: true });
        });
      })
    );
    return;
  }

  // Icons/manifest jaisi cheezein — kam badalti hain, is liye "cache-first"
  // theek hai (tez khulti hain, background mein khud refresh bhi ho jati hain)
  event.respondWith(
    caches.match(key).then(function (cached) {
      var networkFetch = fetch(event.request).then(function (res) {
        putCopy(key, res);
        return res;
      }).catch(function () { return cached; });
      return cached || networkFetch;
    })
  );
});

// Page se "SKIP_WAITING" message aaye (jab user "Update" button dabaye).
// "REFILL": shell ne cache saaf kiya (⟳ Update) — saari files dobara bhar lo,
// warna agle din offline safha khali milta.
self.addEventListener('message', function (event) {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
  if (event.data === 'REFILL') event.waitUntil(caches.open(CACHE_VERSION).then(fill).catch(function () {}));
});
