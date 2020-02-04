workbox.core.skipWaiting();
workbox.core.clientsClaim();
workbox.precaching.precacheAndRoute(self.__precacheManifest);


// This section is based on the following workbox recipe:
// https://developers.google.com/web/tools/workbox/guides/advanced-recipes#provide_a_fallback_response_to_a_route
const CACHE_NAME = 'shell';
const FALLBACK_HTML_URL = '/index.html';

workbox.routing.setCatchHandler(({event}) => {
  // The FALLBACK_URL entries must be added to the cache ahead of time, either
  // via runtime or precaching. If they are precached, then call
  // `matchPrecache(FALLBACK_URL)` (from the `workbox-precaching` package)
  // to get the response from the correct cache.
  //
  // Use event, request, and url to figure out how to respond.
  // One approach would be to use request.destination, see
  // https://medium.com/dev-channel/service-worker-caching-strategies-based-on-request-types-57411dd7652c
  switch (event.request.destination) {
    case 'document':
      return caches.match(FALLBACK_HTML_URL, {
        cacheName: CACHE_NAME,
      });
    break;

    default:
      // If we don't have a fallback, just return an error response.
      return Response.error();
  }
});

self.addEventListener('install', async (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.add(FALLBACK_HTML_URL))
  );
});


workbox.routing.registerRoute(
  /^https:\/\/fonts\.gstatic\.com/,
  new workbox.strategies.CacheFirst({
    cacheName: "google-fonts-webfonts",
    plugins: []
  }),
  "GET"
);
workbox.routing.registerRoute(
  /^https:\/\/fonts\.googleapis\.com/,
  new workbox.strategies.StaleWhileRevalidate({
    cacheName: "google-fonts-stylesheets",
    plugins: []
  }),
  "GET"
);
workbox.routing.registerRoute(
  /\.(?:png|gif|jpg|jpeg|svg)$/,
  new workbox.strategies.StaleWhileRevalidate({
    cacheName: "images",
    plugins: []
  }),
  "GET"
);

workbox.routing.registerRoute(
  /content\.json/,
  new workbox.strategies.NetworkFirst({
    cacheName: "content",
    plugins: []
  }),
  "GET"
);

