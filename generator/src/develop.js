// import * as webpack from "webpack";
const webpack = require("webpack");
const middleware = require("webpack-dev-middleware");
const express = require("express");
const path = require("path");
const HTMLWebpackPlugin = require("html-webpack-plugin");
const CopyPlugin = require("copy-webpack-plugin");
const PrerenderSPAPlugin = require("prerender-spa-plugin");

module.exports = { start, run };
function start() {
  const compiler = webpack(webpackOptions());
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

function run() {
  webpack(webpackOptions()).run();
}

function webpackOptions() {
  return {
    // webpack options
    // entry: "index.html",
    entry: "./index.js",
    mode: "development",
    plugins: [
      new HTMLWebpackPlugin({}),
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
        routes: [
          "/404",
          "/about",
          "/cfp",
          "/cfp/proposals",
          "/",
          "/register",
          "/schedule",
          "/speak-at-elm-conf",
          "/speakers/abadi-kurniawan",
          "/speakers/brooke-angel",
          "/speakers/ian-mackenzie",
          "/speakers/james-carlson",
          "/speakers/james-gary",
          "/speakers/katie-hughes",
          "/speakers/katja-mordaunt",
          "/speakers/liz-krane",
          "/speakers/ryan-frazier",
          "/speakers/tessa-kelly",
          "/travel-and-venue"
        ]
      })
    ],
    output: {
      publicPath: "/"
    },
    resolve: {
      modules: [path.join(__dirname, "src"), "node_modules"],
      extensions: [".js", ".elm", ".scss", ".png", ".html"],
      symlinks: false
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
          loaders: ["style-loader", "css-loader?url=false", "sass-loader"]
        },
        {
          test: /\.css$/,
          exclude: [/elm-stuff/, /node_modules/],
          loaders: ["style-loader", "css-loader?url=false"]
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
          loader: "file-loader"
        },
        {
          test: /\.(jpe?g|png|gif|svg|html)$/i,
          exclude: [/elm-stuff/, /node_modules/],
          loader: "file-loader"
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
    }
  };
}
