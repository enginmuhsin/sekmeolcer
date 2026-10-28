// SekmeÖlçer çevrimdışı önbelleği. Uygulamayı güncellediğinizde SURUM'u değiştirin.
const SURUM = "sekmeolcer-1.2b";
const DOSYALAR = ["./", "./index.html", "./manifest.json", "./ikon-192.png", "./ikon-512.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(SURUM).then(c => c.addAll(DOSYALAR))); self.skipWaiting(); });
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(adlar => Promise.all(adlar.filter(a => a !== SURUM).map(a => caches.delete(a)))));
  self.clients.claim();
});
// Önce internetten dene (güncel sürüm gelsin), internet yoksa önbellekten aç
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  e.respondWith(
    fetch(e.request).then(cevap => {
      if (cevap.ok && new URL(e.request.url).origin === location.origin) { const kopya = cevap.clone(); caches.open(SURUM).then(c => c.put(e.request, kopya)); }
      return cevap;
    }).catch(() => caches.match(e.request).then(c => c || caches.match("./index.html")))
  );
});
