// import * as webpack from "webpack";
const webpack = require("webpack");
const middleware = require("webpack-dev-middleware");
const express = require("express");
const path = require("path");
const HTMLWebpackPlugin = require("html-webpack-plugin");

module.exports = { start };
function start() {
  const compiler = webpack({
    // webpack options
    // entry: "index.html",
    entry: "./index.js",
    plugins: [new HTMLWebpackPlugin({})],
    output: {
      publicPath: "/"
    },
    resolve: {
      modules: [path.join(__dirname, "src"), "node_modules"],
      extensions: [".js", ".elm", ".scss", ".png", ".html"]
    },
    module: {
      rules: [
        {
          test: /\.js$/,
          exclude: /node_modules/,
          use: {
            loader: "babel-loader"
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
            { loader: "elm-hot-webpack-loader" },
            {
              loader: "elm-webpack-loader",
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
  });
  // compiler.watch({}, (error, stats) => {
  //   if (error) {
  //     console.log("error", error);
  //   } else {
  //     console.log("Running!", stats);
  //   }
  // });

  const app = express();

  app.use(middleware(compiler, { publicPath: "/" }));
  // webpack-dev-middleware options
  app.get("/", (req, res) => {
    return res.sendFile(path.join(__dirname, "index.html"));
  });
  app.listen(3000, () => console.log("Example listening on port 3000!"));
  // https://stackoverflow.com/questions/43667102/webpack-dev-middleware-and-static-files
  app.use(express.static(__dirname + "/path-to-static-folder"));

  // compiler.run();
}

start();
