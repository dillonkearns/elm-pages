// import * as webpack from "webpack";
const webpack = require("webpack");
const middleware = require("webpack-dev-middleware");
const express = require("express");
const path = require("path");

export function start() {
  const compiler = webpack({
    // webpack options
    entry: "index.html",
    plugins: [],
    resolve: {
      modules: [path.join(__dirname, "src"), "node_modules"],
      extensions: [".js", ".elm", ".scss", ".png"]
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
          test: /\.(jpe?g|png|gif|svg)$/i,
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
  const app = express();

  app.use(middleware(compiler, { publicPath: "/" }));
  // webpack-dev-middleware options

  app.listen(3000, () => console.log("Example listening on port 3000!"));
}
