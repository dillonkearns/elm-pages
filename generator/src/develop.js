const webpack = require("webpack");
const elmMinify = require("elm-minify");
const middleware = require("webpack-dev-middleware");
const express = require("express");
const path = require("path");
const HTMLWebpackPlugin = require("html-webpack-plugin");
const CopyPlugin = require("copy-webpack-plugin");
const PrerenderSPAPlugin = require("prerender-spa-plugin");
const merge = require("webpack-merge");
const { GenerateSW } = require("workbox-webpack-plugin");
const FaviconsWebpackPlugin = require("favicons-webpack-plugin");

module.exports = { start, run };
function start({ routes, debug }) {
  const compiler = webpack(webpackOptions(false, routes, { debug }));
  const app = express();

  app.use(middleware(compiler, { publicPath: "/" }));

  app.use("*", function(req, res, next) {
    // don't know why this works, but it does
    // see: https://github.com/jantimon/html-webpack-plugin/issues/145#issuecomment-170554832
    var filename = path.join(compiler.outputPath, "index.html");
    compiler.outputFileSystem.readFile(filename, function(err, result) {
      if (err) {
        return next(err);
      }
      res.set("content-type", "text/html");
      res.send(result);
      res.end();
    });
  });

  app.listen(3000, () =>
    console.log("🚀 elm-pages develop running http://localhost:3000")
  );
  // https://stackoverflow.com/questions/43667102/webpack-dev-middleware-and-static-files
  // app.use(express.static(__dirname + "/path-to-static-folder"));
}

function run({ routes }, callback) {
  webpack(webpackOptions(true, routes, { debug: false })).run((err, stats) => {
    if (err) {
      console.error(err);
      process.exit(1);
    } else {
      callback();
    }

    console.log(
      stats.toString({
        chunks: false, // Makes the build much quieter
        colors: true // Shows colors in the console
      })
    );
  });
}

function webpackOptions(production, routes, { debug }) {
  const common = {
    // webpack options
    // entry: "index.html",
    entry: { hello: "./index.js" },
    mode: production ? "production" : "development",
    plugins: [
      new HTMLWebpackPlugin({
        inject: "head",
        // template: require.resolve("./template.html")
        // template: require.resolve(path.resolve(__dirname, "template.html"))
        template: path.resolve(__dirname, "template.html")
      }),
      new CopyPlugin([
        {
          from: "static/**/*",
          transformPath(targetPath, absolutePath) {
            // TODO this is a hack... how do I do this with proper config of `to` or similar?
            return targetPath.substring(targetPath.indexOf("/") + 1);
          }
        }
      ]),
      new PrerenderSPAPlugin({
        // Required - The path to the webpack-outputted app to prerender.
        // staticDir: "./dist",
        staticDir: path.join(process.cwd(), "dist"),
        // Required - Routes to render.
        routes: routes,
        renderAfterDocumentEvent: "prerender-trigger"
      }),
      new GenerateSW({
        include: [/^index.html$/, /\.js$/],
        navigateFallback: "index.html",
        swDest: "service-worker.js",
        runtimeCaching: [
          {
            // urlPattern: /^https:\/\/fonts\.googleapis\.com/,
            urlPattern: /^https:\/\/fonts\.gstatic\.com/,
            handler: "CacheFirst",
            options: {
              cacheName: "fonts"
            }
          },
          {
            urlPattern: /\.(?:png|gif|jpg|jpeg|svg)$/,
            handler: "CacheFirst",
            options: {
              cacheName: "images"
            }
          }
        ]
      }),
      new FaviconsWebpackPlugin({
        logo: path.resolve(process.cwd(), "./icon.svg"),
        favicons: {
          path: "/", // Path for overriding default icons path. `string`
          appName: null, // Your application's name. `string`
          appShortName: null, // Your application's short_name. `string`. Optional. If not set, appName will be used
          appDescription: null, // Your application's description. `string`
          developerName: null, // Your (or your developer's) name. `string`
          developerURL: null, // Your (or your developer's) URL. `string`
          dir: "auto", // Primary text direction for name, short_name, and description
          lang: "en-US", // Primary language for name and short_name
          background: "#fff", // Background colour for flattened icons. `string`
          theme_color: "#fff", // Theme color user for example in Android's task switcher. `string`
          appleStatusBarStyle: "black-translucent", // Style for Apple status bar: "black-translucent", "default", "black". `string`
          display: "standalone", // Preferred display mode: "fullscreen", "standalone", "minimal-ui" or "browser". `string`
          orientation: "any", // Default orientation: "any", "natural", "portrait" or "landscape". `string`
          scope: "/", // set of URLs that the browser considers within your app
          start_url: "/?homescreen=1", // Start URL when launching the application from a device. `string`
          version: "1.0", // Your application's version string. `string`
          logging: false, // Print logs to console? `boolean`
          pixel_art: false, // Keeps pixels "sharp" when scaling up, for pixel art.  Only supported in offline mode.
          loadManifestWithCredentials: false, // Browsers don't send cookies when fetching a manifest, enable this to fix that. `boolean`
          icons: {
            // Platform Options:
            // - offset - offset in percentage
            // - background:
            //   * false - use default
            //   * true - force use default, e.g. set background for Android icons
            //   * color - set background for the specified icons
            //   * mask - apply mask in order to create circle icon (applied by default for firefox). `boolean`
            //   * overlayGlow - apply glow effect after mask has been applied (applied by default for firefox). `boolean`
            //   * overlayShadow - apply drop shadow after mask has been applied .`boolean`
            //
            android: true, // Create Android homescreen icon. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
            appleIcon: true, // Create Apple touch icons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
            appleStartup: false, // Create Apple startup images. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
            coast: false, // Create Opera Coast icon. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
            favicons: true, // Create regular favicons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
            firefox: false, // Create Firefox OS icons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
            windows: false, // Create Windows 8 tile icons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
            yandex: false // Create Yandex browser icon. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
          }
        }
      })
    ],
    output: {
      publicPath: "/"
    },
    resolve: {
      modules: [path.resolve(process.cwd(), `./node_modules`)],
      extensions: [".js", ".elm", ".scss", ".png", ".html"]
    },
    module: {
      rules: [
        {
          test: /\.js$/,
          exclude: /node_modules/,
          use: {
            // loader: "babel-loader"
            loader: require.resolve("babel-loader")
          }
        },
        {
          test: /\.scss$/,
          exclude: [/elm-stuff/, /node_modules/],
          // see https://github.com/webpack-contrib/css-loader#url
          loaders: [
            require.resolve("style-loader"),
            require.resolve("css-loader"),
            require.resolve("sass-loader")
          ]
        },
        {
          test: /\.css$/,
          exclude: [/elm-stuff/, /node_modules/],
          loaders: [
            require.resolve("style-loader"),
            require.resolve("css-loader")
          ]
        },
        {
          test: /\.woff(2)?(\?v=[0-9]\.[0-9]\.[0-9])?$/,
          exclude: [/elm-stuff/, /node_modules/],
          loader: "url-loader",
          options: {
            limit: 10000,
            mimetype: "application/font-woff"
          }
        },
        {
          test: /\.(ttf|eot|svg)(\?v=[0-9]\.[0-9]\.[0-9])?$/,
          exclude: [/elm-stuff/, /node_modules/],
          loader: require.resolve("file-loader")
        },
        {
          test: /\.(jpe?g|png|gif|svg|html)$/i,
          exclude: [/elm-stuff/, /node_modules/],
          loader: require.resolve("file-loader")
        }
      ]
    },
    stats: {
      // copied from `'minimal'`
      all: false,
      modules: true,
      maxModules: 0,
      errors: true,
      warnings: true,
      // our additional options
      moduleTrace: true,
      errorDetails: true
    }
  };
  if (production) {
    return merge(common, {
      module: {
        rules: [
          {
            test: /\.elm$/,
            exclude: [/elm-stuff/, /node_modules/],
            use: {
              loader: "elm-webpack-loader",
              options: {
                optimize: true
              }
            }
          }
        ]
      }
    });
  } else {
    return merge(common, {
      module: {
        rules: [
          {
            test: /\.elm$/,
            exclude: [/elm-stuff/, /node_modules/],
            use: [
              { loader: "elm-hot-webpack-loader" },
              {
                loader: "elm-webpack-loader",
                options: {
                  // add Elm's debug overlay to output?
                  debug: debug,
                  //
                  forceWatch: true
                }
              }
            ]
          }
        ]
      }
    });
  }
}
