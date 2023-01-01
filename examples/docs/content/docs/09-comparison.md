# Comparison

## Lamdera

The way I've been thinking about it is that elm-pages v3 specializes in what happens before init:

- Pre-rendering the HTML and including meta tags
- Pulling in BackendTasks and avoiding extra intermediary states
- Choosing how to handle incoming HTTP requests with the Request.Parser API (parsing the incoming request's method, query params, headers, cookies, etc.)
- Returning low-level HTTP responses (setting cookies, doing redirects)

And Lamdera specializes in what happens after init:

- Sending real-time data to the client
- Managing multiple connected clients
- Persisting data automatically
- Migrating data

It's possible that Lamdera will adopt some of those elm-pages features at some point (and I hope it does, that would be incredible!).

## elm-spa
