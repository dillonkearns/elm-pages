workbox.core.skipWaiting();
workbox.core.clientsClaim();
workbox.precaching.precacheAndRoute(self.__precacheManifest);


// This section is based on the following workbox recipe:
// https://developers.google.com/web/tools/workbox/guides/advanced-recipes#provide_a_fallback_response_to_a_route
// and this stackoverflow answer: https://stackoverflow.com/a/53597107
const CACHE_NAME = 'shell';
const FALLBACK_HTML_URL = '/index.html';

let networkOnly = new workbox.strategies.NetworkOnly();

const navigationHandler = async (args) => {
  try {
    const response = await networkOnly.handle(args);
    return response || await caches.match(FALLBACK_HTML_URL);
  } catch (error) {
    return await caches.match(FALLBACK_HTML_URL);
  }
};

workbox.routing.registerRoute(
  new workbox.routing.NavigationRoute(navigationHandler)
);



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

