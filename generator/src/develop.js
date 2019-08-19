const webpack = require("webpack");
const elmMinify = require("elm-minify");
const middleware = require("webpack-dev-middleware");
const path = require("path");
const HTMLWebpackPlugin = require("html-webpack-plugin");
const CopyPlugin = require("copy-webpack-plugin");
const PrerenderSPAPlugin = require("prerender-spa-plugin");
const merge = require("webpack-merge");
const { GenerateSW } = require("workbox-webpack-plugin");
const FaviconsWebpackPlugin = require("favicons-webpack-plugin");
const webpackDevServer = require("webpack-dev-server");

class AddFilesPlugin {
  constructor(filesList) {
    this.filesList = filesList;
  }
  apply(compiler) {
    compiler.hooks.afterCompile.tap("AddFilesPlugin", compilation => {
      this.filesList.forEach(file => {
        console.log("adding file ", file);
        compilation.assets[`${file.name}/content.txt`] = {
          source: function() {
            return file.content;
          },
          size: function() {
            file.content.length;
          }
        };
      });
    });
  }
}

module.exports = { start, run };
function start({ routes, debug, manifestConfig }) {
  const config = webpackOptions(false, routes, { debug, manifestConfig });
  const compiler = webpack(config);

  const options = {
    contentBase: "./dist",
    hot: true,
    inline: false,
    host: "localhost"
  };

  webpackDevServer.addDevServerEntrypoints(config, options);
  const server = new webpackDevServer(webpack(config), options);

  server.listen(3000, "localhost", () => {
    console.log("🚀 elm-pages develop on http://localhost:3000");
  });
}

function run({ routes, fileContents, manifestConfig }, callback) {
  webpack(
    webpackOptions(true, routes, { debug: false, fileContents, manifestConfig })
  ).run((err, stats) => {
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

function webpackOptions(
  production,
  routes,
  { debug, fileContents, manifestConfig }
) {
  const common = {
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
        logo: path.resolve(process.cwd(), `./${manifestConfig.sourceIcon}`),
        favicons: {
          path: "/", // Path for overriding default icons path. `string`
          appName: manifestConfig.name, // Your application's name. `string`
          appShortName: manifestConfig.short_name, // Your application's short_name. `string`. Optional. If not set, appName will be used
          appDescription: manifestConfig.description, // Your application's description. `string`
          developerName: null, // Your (or your developer's) name. `string`
          developerURL: null, // Your (or your developer's) URL. `string`
          dir: "auto", // Primary text direction for name, short_name, and description
          lang: "en-US", // Primary language for name and short_name
          background: manifestConfig.background_color, // Background colour for flattened icons. `string`
          theme_color: manifestConfig.theme_color, // Theme color user for example in Android's task switcher. `string`
          appleStatusBarStyle: "black-translucent", // Style for Apple status bar: "black-translucent", "default", "black". `string`
          display: manifestConfig.display, // Preferred display mode: "fullscreen", "standalone", "minimal-ui" or "browser". `string`
          orientation: manifestConfig.orientation, // Default orientation: "any", "natural", "portrait" or "landscape". `string`
          scope: manifestConfig.serviceworker.scope, // set of URLs that the browser considers within your app
          start_url: manifestConfig.start_url, // Start URL when launching the application from a device. `string`
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
      plugins: [
        new AddFilesPlugin(
          fileContents.map(([path, content]) => {
            return {
              name: path,
              content: content
            };
          })
        )
      ],
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
