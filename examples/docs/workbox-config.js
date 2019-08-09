module.exports = {
  globDirectory: "dist/",
  globPatterns: ["**/*.{html,js}"],
  swDest: "dist/service-worker.js",
  runtimeCaching: [
    {
      // Match any request that ends with .png, .jpg, .jpeg or .svg.
      // urlPattern: /^https:\/\/fonts\.googleapis\.com/,
      urlPattern: /^https:\/\/fonts\.gstatic\.com/,

      // Apply a cache-first strategy.
      handler: "CacheFirst",

      options: {
        // Use a custom cache name.
        cacheName: "fonts"
      }
    }
  ]
};
