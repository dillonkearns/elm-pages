# Use the Platform

`elm-pages` apps provide the best experience to both developers and users when we leverage the platform we're building on top of: the Web.

## URLs

The web has built-in mechanisms for state management. Often client-side applications reinvent the wheel and move state into JavaScript (or the `Model` in a a vanilla Elm app).

For example, you might have some implicit state if you click through some tabs or apply some filters on your current page. Let's consider a product search page with a search query and a UI with filters.

If you enter a search query and apply some filters, is that reflected in the URL? If you refresh the page, will you lose your search context? This can be a frustrating experience, and you're also missing out on some of the benefits of building a web application. If you make use of URL state, you can send a coworker or a friend a link, or bookmark it. It's a powerful productivity tool, and one that many users will be familiar with no extra training.

When you leverage these features such as using the URL to manage state, you are going with the grain and will have a simpler code in your `elm-pages` app as well since `elm-pages` is designed to leverage the web platform.

## Cookies

Cookie-based sessions provide some benefits over client-side authentication methods like JWT Tokens. JWT tokens need to be appended to your HTTP requests manually when you perform requests to your API. They also need some place to store them on the client, often using LocalStorage. This can be a security risk, and it also means that you need to write more code to handle the authentication flow.

With cookie-based sessions, your requests to your server automatically have the session cookie attached. This means that you don't need to write any extra code to store and retrieve the token and ensure that it is attached to API requests. It also has security benefits because you can use [HTTP-only cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#httponly) (the default when you use the [`Server.Session` API](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Session)). HTTP-only cookies are only accessible to the server that initially set the cookie (it can't be accessed through JavaScript with `document.cookie`, or through LocalStorage).

## Redirects

Elm apps work best when we can check for pre-conditions and filter out invalid states and violations of constraints at the top-level. For example, if a user is not logged in and is trying to access the user settings page, we want to avoid checking a `Maybe` or `RemoteData` everywhere we display the current user settings in that Route.

Redirects are a great mechanism that can help you make intuitive user experiences in cases like this. If you're not logged in, you can redirect to the login route. If you're logged in, then we can get the user settings data and render the page.

In server-rendered routes, you can return a [`Server.Response`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Response) where you either resolve to the `Data` needed for that Route, or alternatively redirect. By redirecting, you short-circuiting the `Data` for that Route by instead navigating to another Route. You can create a redirect Response using [Server.Response.temporaryRedirect](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Response#temporaryRedirect), or using the code in the generated `Route` module `Route.redirectTo` (this takes an argument of your `Route` type so it is more type-safe).

## Forms

`elm-pages` provides an abstraction for building progressively-enhanced forms. By using Forms, you can write a declarative definition of your Form with its client-side validations and view rendering logic, and then let the `elm-pages` framework manage the Form state for you to give dynamic client-side errors. You can receive the form data and use the same form definition to parse the Form into a nice Elm data structure (or validation errors) in your `action`. `elm-pages` takes care of progressively enhancing the form submissions for you, so it will send the raw form data to your Elm Backend without a full page reload. However, since it uses progressive enhancement, the form submission will still work if the user submits a form before the JavaScript has finished loading.

Because we are using the built-in Web concept of form data, we can avoid doing extra glue code to serialize/deserialize our form and can instead build it in a more declarative way that gives us a semantic form with an accessible user experience. Read more about Forms in [the Forms API docs](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Pages-Form).
