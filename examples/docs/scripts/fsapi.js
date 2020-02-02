#!/usr/bin/env node
const express = require('express')
const fsMiddleware = require('netlify-cms-backend-fs/dist/fs')
const app = express()
const port = 3001
const host = 'localhost'

app.use(express.static('.')) // root of our site

var allowCrossDomain = function(req, res, next) {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  next();
}
app.use(allowCrossDomain);

fsMiddleware(app) // sets up the /api proxy paths

app.listen(port, () => console.log(
    `
    Server listening at http://${host}:${port}/
    API listening at http://${host}:${port}/api
    `
))

