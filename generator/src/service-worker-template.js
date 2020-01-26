workbox.core.skipWaiting();
workbox.core.clientsClaim();
workbox.precaching.precacheAndRoute(self.__precacheManifest);
workbox.routing.registerNavigationRoute(
  workbox.precaching.getCacheKeyForURL("/index.html"),
  {
    blacklist: [/admin/, /\./]
  }
);
workbox.routing.registerRoute(
  /^https:\/\/fonts\.gstatic\.com/,
  new workbox.strategies.CacheFirst({
    cacheName: "google-fonts-webfonts",
    plugins: []
  }),
  "GET"
);
workbox.routing.registerRoute(
  /.js$/,
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
  new workbox.strategies.StaleWhileRevalidate({
    cacheName: "images",
    plugins: []
  }),
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

self.addEventListener("install", event => {
  // TODO load the list of content files to warm up in the cache here

  // TODO store content in a cache that is hashed based on the webpack bundle hash,
  // then delete the old cache on activate
  const contentUrls = [
    // "/blog/content.json",
    // "/blog/types-over-conventions/content.json"
  ];
  const coreUrls = ["/main.js"];
  const preloadContent = caches
    .open("content")
    .then(cache => cache.addAll(contentUrls));
  const preloadCore = caches
    .open("shell")
    .then(cache => cache.addAll(coreUrls));
  const warmUp = Promise.all([preloadContent, preloadCore]);
  return warmUp;
});
