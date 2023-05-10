# Adapters

If you only use pre-rendered routes in your `elm-pages` app, then `elm-pages build` will generate its output in a `dist/` folder and you can use that output with your static hosting method of choice.

However, if you are using server-rendered routes, you will need a way to take the server-side code for your `elm-pages` app, and glue that together to run in the context of your server. The core code for rendering the HTML for your `elm-pages` app given an incoming request (URL, method, headers, etc.) is the same for any app. What differs is:

- **Request** - What is the format of the raw request data?
- **Response** - How do you take the response from the `elm-pages` app and turn it into the response type that your server or hosting provider needs? For example, a Netlify Serverless function has a different contract for sending responses than an Express server.
- **Wiring** - Where do you put files and code in order to run this code in the context of your server or hosting provider? Your server or hosting provider may have different conventions for where to put your code and how to run it, and you will likely need to move some files and generate some glue code to wire things up.

## The Adapter API
