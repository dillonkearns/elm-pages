# Adapters

If you only use pre-rendered routes in your `elm-pages` app, then `elm-pages build` will generate its output in a `dist/` folder and you can use that output with your static hosting method of choice.

However, if you are using server-rendered routes, you will need a way to take the server-side code for your `elm-pages` app, and glue that together to run in the context of your server. The core code for rendering the HTML for your `elm-pages` app given an incoming request (URL, method, headers, etc.) is the same for any app. What differs is:

- **Request** - What is the format of the raw request data?
- **Response** - How do you take the response from the `elm-pages` app and turn it into the response type that your server or hosting provider needs? For example, a Netlify Serverless function has a different contract for sending responses than an Express server.
- **Wiring** - Where do you put files and code in order to run this code in the context of your server or hosting provider? Your server or hosting provider may have different conventions for where to put your code and how to run it, and you will likely need to move some files and generate some glue code to wire things up.

## Built-in Adapters

`elm-pages` currently has a Netlify adapter. You can use it by importing it in your `elm-pages.config.mjs` file:

```js
import adapter from "elm-pages/adapter/netlify.js";

export default {
  adapter,
};
```

## The Adapter API

You can also use the adapter API directly to build your own adapter. An adapter is an async function that can execute any scripting setup needed to move/copy/generate files or do other setup to prepare an `elm-pages` app for deployment on a given hosting provider. The function return value is ignored, it is just an async function that can perform some actions.

You can see [the full implementation of the Netlify adapter script](https://github.com/dillonkearns/elm-pages-v3-beta/blob/master/adapter/netlify.js) for reference.

It is run after `elm-pages build` has generated the `dist/` folder, so you can assume that the `dist/` folder exists and contains the output of `elm-pages build`.

The function is passed an object with the following properties:

```js
export default async function run({
  renderFunctionFilePath,
  routePatterns,
  apiRoutePatterns,
}) {
  // do work to adapt for your hosting provider here
}
```

### `renderFunctionFilePath`

The path to the file that contains the function that renders the HTML for your `elm-pages` app. This is the file that you will need to import and call in your server code. It contains a single default export which is an async function. It takes an HTTP request object and returns an elm-pages response object

Here is an example of invoking the elm-pages render function, though the specifics will depend on your context, including:

- Where you put the `renderFunctionFilePath`
- How you import the render function
- Your hosting platform's API for working with the incoming HTTP request, and return an HTTP response

```js
import * as elmPages from "<renderFunctionFilePath>"; // your script will need to decide where to put this file and how to import it

async function render(event, context) {
  try {
    const renderResult = await elmPages.render(reqToJson(event));
    const { headers, statusCode } = renderResult;

    if (renderResult.kind === "bytes") {
      return {
        body: Buffer.from(renderResult.body).toString("base64"),
        isBase64Encoded: true,
        multiValueHeaders: {
          "Content-Type": ["application/octet-stream"],
          "x-powered-by": ["elm-pages"],
          ...headers,
        },
        statusCode,
      };
    } else if (renderResult.kind === "api-response") {
      return {
        body: renderResult.body,
        multiValueHeaders: headers,
        statusCode,
        isBase64Encoded: renderResult.isBase64Encoded,
      };
    } else {
      return {
        body: renderResult.body,
        multiValueHeaders: {
          "Content-Type": ["text/html"],
          "x-powered-by": ["elm-pages"],
          ...headers,
        },
        statusCode,
      };
    }
  } catch (error) {
    console.error(error);
    return {
      body: "<body><h1>Error</h1><pre>Unexpected Error</pre></body>,
      statusCode: 500,
      multiValueHeaders: {
        "Content-Type": ["text/html"],
        "x-powered-by": ["elm-pages"],
      },
    };
  }
}

/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} req
 * @returns {{method: string; rawUrl: string; body: string?; headers: Record<string, string>; multiPartFormData: unknown }}
 */
function reqToJson(req) {
  return {
    method: req.httpMethod,
    headers: req.headers,
    rawUrl: req.rawUrl,
    body: req.body,
    multiPartFormData: null,
  };
}
```

### `routePatterns`

These is a list of routes for the `elm-pages` app. Depending on your hosting provider, you might want to use it to

- Generate a route manifest file and put it in a folder that your host uses for routing (for a configuration-based routing system)
- Generate files for each route that invokes the elm-pages render function (for a file-based routing system)
- Generate a redirects file to invoke the render function through HTTP redirects (like in this example below)

```js
function isServerSide(route) {
  return (
    route.kind === "prerender-with-fallback" || route.kind === "serverless"
  );
}

const routeRedirects = routePatterns
  .filter(isServerSide)
  .map((route) => {
    if (route.kind === "prerender-with-fallback") {
      return `${route.pathPattern} /.netlify/builders/render 200
${route.pathPattern}/content.dat /.netlify/builders/render 200`;
    } else {
      return `${route.pathPattern} /.netlify/functions/server-render 200
${route.pathPattern}/content.dat /.netlify/functions/server-render 200`;
    }
  })
  .join("\n");

function isServerSide(route) {
  return (
    route.kind === "prerender-with-fallback" || route.kind === "serverless"
  );
}
```

## `apiRoutePatterns`

```js
const apiRouteRedirects = apiRoutePatterns
  .filter(isServerSide)
  .map((apiRoute) => {
    if (apiRoute.kind === "prerender-with-fallback") {
      return `${apiPatternToRedirectPattern(
        apiRoute.pathPattern
      )} /.netlify/builders/render 200`;
    } else if (apiRoute.kind === "serverless") {
      return `${apiPatternToRedirectPattern(
        apiRoute.pathPattern
      )} /.netlify/functions/server-render 200`;
    } else {
      throw "Unhandled API Server Route";
    }
  })
  .join("\n");

function isServerSide(route) {
  return (
    route.kind === "prerender-with-fallback" || route.kind === "serverless"
  );
}
```
