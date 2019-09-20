workbox.core.skipWaiting();
workbox.core.clientsClaim();
workbox.routing.registerNavigationRoute("index.html");

// workbox.routing.registerNavigationRoute(
//   workbox.precaching.getCacheKeyForURL("index.html")
// );

workbox.routing.registerRoute(
  /^https:\/\/fonts\.gstatic\.com/,
  new workbox.strategies.CacheFirst({
    cacheName: "google-fonts-webfonts",
    plugins: []
  }),
  "GET"
);
workbox.routing.registerRoute(
  /(^index\.html$|.js$)/,
  new workbox.strategies.NetworkFirst({
    cacheName: "shell",
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
  new workbox.strategies.CacheFirst({ cacheName: "images", plugins: [] }),
  "GET"
);
workbox.routing.registerRoute(
  /\.(?:png|gif|jpg|jpeg|svg)$/,
  new workbox.strategies.CacheFirst({ cacheName: "images", plugins: [] }),
  "GET"
);

workbox.routing.registerRoute(
  /content\.txt$/,
  new workbox.strategies.NetworkFirst({
    cacheName: "content",
    plugins: []
  }),
  "GET"
);

workbox.precaching.precacheAndRoute(self.__precacheManifest);
