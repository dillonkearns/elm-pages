module FatalError exposing (FatalError, fromString, recoverable)

{-| The Elm language doesn't have the concept of exceptions or special control flow for errors. It just has
Custom Types, and by convention types like `Result` and the `Err` variant are used to represent possible failure states
and combine together different error states.

`elm-pages` doesn't change that, Elm still doesn't have special exception control flow at the language level. It does have
a type, which is just a regular old Elm type, called `FatalError`. Why? Because this plain old Elm type does have one
special characteristic - the `elm-pages` framework knows how to turn it into an error message. This becomes interesting
because an `elm-pages` app has several places that accept a value of type `BackendTask FatalError.FatalError value`.
This design lets the `elm-pages` framework do some of the work for you.

For example, if you wanted to handle possible errors to present them to the user

    type alias Data =
        String

    data : RouteParams -> BackendTask FatalError Data
    data routeParams =
        BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "description" Decode.string)
            |> BackendTask.onError
                (\error ->
                    case FatalError.unwrap error of
                        BackendTask.Http.BadStatus metadata string ->
                            if metadata.statusCode == 401 || metadata.statusCode == 403 || metadata.statusCode == 404 then
                                BackendTask.succeed "Either this repo doesn't exist or you don't have access to it."

                            else
                                -- we're only handling these expected error cases. In the case of an HTTP timeout,
                                -- we'll let the error propagate as a FatalError
                                BackendTask.fail error |> BackendTask.allowFatal

                        _ ->
                            BackendTask.fail error |> BackendTask.allowFatal
                )

This can be a lot of work for all possible errors, though. If you don't expect this kind of error (it's an _exceptional_ case),
you can let the framework handle it if the error ever does unexpectedly occur.

    data : RouteParams -> BackendTask FatalError Data
    data routeParams =
        BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "description" Decode.string)
            |> BackendTask.allowFatal

This is especially useful for pages generated at build-time (`RouteBuilder.preRender`) where you want the build
to fail if anything unexpected happens. With pre-rendered routes, you know that these error cases won't
be seen by users, so it's often a great idea to just let the framework handle these unexpected errors so a developer can
debug them and see what went wrong. In the example above, maybe we are only pre-rendering pages for a set of known
GitHub Repositories, so a Not Found or Unauthorized HTTP error would be unexpected and should stop the build so we can fix the
issue.

In the case of server-rendered Routes (`RouteBuilder.serverRender`), `elm-pages` will show your 500 error page
when these errors occur.

@docs FatalError, fromString, recoverable

-}

import Pages.Internal.FatalError


{-| -}
type alias FatalError =
    Pages.Internal.FatalError.FatalError


{-| -}
build : { title : String, body : String } -> FatalError
build info =
    Pages.Internal.FatalError.FatalError info


{-| -}
fromString : String -> FatalError
fromString string =
    build
        { title = "Custom Error"
        , body = string
        }


{-| -}
recoverable : { title : String, body : String } -> error -> { fatal : FatalError, recoverable : error }
recoverable info value =
    { fatal = build info
    , recoverable = value
    }
