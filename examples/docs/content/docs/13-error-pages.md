# Error Pages

In your server-rendered routes, you can choose to short-circuit rendering your route and instead render an error page. This is useful for things like 404 pages, or 500 pages, or even custom error pages for specific errors. In order to render your route, you must resolve to the `Data` type in your Route module with [Server.Response.render](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Response#render).

For example, let's say you have the following Route module:

```elm
module Route.User.UserId_ exposing (..)

import UserProfile exposing (UserProfile)

type alias Data = { profile : UserProfile }

data :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed
    (UserProfile.find routeParams.userId
        |> BackendTask.map
            (\maybeProfile ->
            case maybeProfile of
            Just foundProfile ->
                Server.Response.render
                    { profile = profile }
            Nothing ->
                Server.Response.errorPage ErrorPage.NotFound
            )
    )
```

In this example, we are attempting to lookup a user profile by id. If we find the profile, we render the route. If we don't find the profile, we render a 404 error page. A good rule of thumb is that if you are able to successfully resolve the `Data` for your Route, use `Server.Response.render`. If you are unable to resolve the `Data` for your Route, use [`Server.Response.errorPage`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Response#errorPage).

## Custom Error Types

Your app must define a module `app/ErrorPage.elm` with a type exposed called `ErrorPage`. However, you can define the `ErrorPage` type with custom error pages and data specific to rendering different error cases.

For example, you might have a generic 404 and 500 page, but in addition to that you might want to define an ErrorPage for viewing a paid resource that the user doesn't have access to. You might define your `ErrorPage` type like this:

```elm
type PlanStatus
    = FreeTrialExpired
    | ProPlanExpired
    | NotLoggedIn
    | NotSubscribed

type ErrorPage
    = NotFound
    | InternalError String
    | PaywallAccessError { resource : PaidResource, planStatus : PlanStatus }
```

Then you could render the error page like this:

```elm
data :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    withProAccess
    (\access ->
        case access of
            Ok () ->
                resolvePageData routeParams

            Err planStatus ->
                Server.Response.errorPage
                    (ErrorPage.PaywallAccessError
                        { resource = routeParams.resource
                        , planStatus = planStatus
                        }
                    )
    )
```

This pattern allows us to use `BackendTask`'s to resolve data such as the plan status (this might involve a database request or API call to check for the current user's status), and then pass that data through to be rendered via our `ErrorPage` type. That means that we can resolve data specific to the `ErrorPage` while still short-circuiting our `Route` rendering and **not** resolving our Route's `Data` type.

## Stateful Error Pages

`ErrorPage`'s have access to a self-contained Elm Architecture (Model/view/update), so you can make interactive `ErrorPage`'s.

```elm
type Msg
    = Increment


type alias Model =
    { count : Int
    }


init : ErrorPage -> ( Model, Effect Msg )
init errorPage =
    ( { count = 0 }
    , Effect.none
    )


update : ErrorPage -> Msg -> Model -> ( Model, Effect Msg )
update errorPage msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }, Effect.none )

view : ErrorPage -> Model -> View Msg
view error model =
    div []
    [ button [ onClick Increment ] []
    ]
```

## `FatalError`'s

You may not want to explicitly handle every possible error case and resolve it to an `ErrorPage` type for unexpected corner cases. For example, if you depend on an API to render your Route and don't expect it to fail, or can't do anything meaningful except for showing an error page if it fails, you can resolve to a `FatalError`. Note that a pre-rendered static route will fail the build if it resolves to a `FatalError`, resulting in a debugging error message displayed in the console - `FatalError`'s are a great tool for static routes because you can prevent bad data going live to the site and give yourself the opportunity to retry or fix the build when rare edge cases occur.

With server-rendered routes, when your Route module's `data` resolves to a `FatalError`, it will render your `ErrorPage.internalError` page. You can customize how your internal error page is rendered, but the downside is that it will render a generic error page with a String for context without giving you the opportunity to pass through meaningful context (use `Server.Response.errorPage` if you want to pass through meaningful context).

Here's an example of how you can use `FatalError`'s:

```elm
callMyApi : RouteParams -> BackendTask Never (Result Error ApiResponse)
callMyApi = -- ...

data : RouteParams -> Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.succeed
        (callMyApi routeParams
            |> BackendTask.map (\response ->
            case response of
                Ok apiResponse ->
                    renderMyPage apiResponse
                Err error ->
                    BackendTask.fail
                    (FatalError.fromString "Error accessing API, please try again")
            )
        )
```

It's important to note that the `String` for `ErrorPage.internalError` could come from propogating a `FatalError`, so it's generally not a good practice to display these error messages to users (though it is a good idea to display them in your dev server's 500 pages, or log them to an error reporting service).

```elm
data : RouteParams -> Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.succeed
        (BackendTask.Http.getJson apiUrl apiDecoder
            |> BackendTask.allowFatal
            |> BackendTask.andThen renderMyPage
        )
```

In this case, we're allowing the `FatalError` from the `BackendTask.Http` error to propogate through. This will result in a fairly low-level error message that we should avoid presenting to the user.
