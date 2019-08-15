const webpack = require("webpack");
const middleware = require("webpack-dev-middleware");
const express = require("express");
const path = require("path");
const HTMLWebpackPlugin = require("html-webpack-plugin");
const CopyPlugin = require("copy-webpack-plugin");
const PrerenderSPAPlugin = require("prerender-spa-plugin");

module.exports = { start, run };
function start({ routes }) {
  const compiler = webpack(webpackOptions(true, routes));
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

function run({ routes }) {
  webpack(webpackOptions(false, routes)).run((err, stats) => {
    if (err) {
      console.error(err);
      process.exit(1);
    }

    console.log(
      stats.toString({
        chunks: false, // Makes the build much quieter
        colors: true // Shows colors in the console
      })
    );
  });
}

function webpackOptions(production, routes) {
  return {
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
        },
        {
          test: /\.elm$/,
          exclude: [/elm-stuff/, /node_modules/],
          use: [
            { loader: require.resolve("elm-hot-webpack-loader") },
            {
              loader: require.resolve("elm-webpack-loader"),
              options: {
                // add Elm's debug overlay to output?
                debug: false,
                forceWatch: true
              }
            }
          ]
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
}
