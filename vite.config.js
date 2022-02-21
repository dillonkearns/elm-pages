export default defineConfig({
  build: {
    // generate manifest.json in outDir
    manifest: true,

    rollupOptions: {
      // overwrite default .html entry

      input:
        "/Users/dillonkearns/src/github.com/dillonkearns/elm-pages/examples/docs/public/index.js",
    },
  },
});
