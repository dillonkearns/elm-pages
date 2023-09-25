module BackendTask.Custom exposing
    ( run
    , Error(..)
    , timeDecoder, dateDecoder
    )

{-| In a vanilla Elm application, ports let you either send or receive JSON data between your Elm application and the JavaScript context in the user's browser at runtime.

With `BackendTask.Custom`, you send and receive JSON to JavaScript running in NodeJS. As with any `BackendTask`, Custom BackendTask's are either run at build-time (for pre-rendered routes) or at request-time (for server-rendered routes). See [`BackendTask`](BackendTask) for more about the
lifecycle of `BackendTask`'s.

This means that you can call shell scripts, run NPM packages that are installed, or anything else you could do with NodeJS to perform custom side-effects, get some data, or both.

A `BackendTask.Custom` will call an async JavaScript function with the given name from the definition in a file called `custom-backend-task.js` in your project's root directory. The function receives the input JSON value, and the Decoder is used to decode the return value of the async function.

@docs run

Here is the Elm code and corresponding JavaScript definition for getting an environment variable (or an `FatalError BackendTask.Custom.Error` if it isn't found). In this example,
we're using `BackendTask.allowFatal` to let the framework treat that as an unexpected exception, but we could also handle the possible failures of the `FatalError` (see [`FatalError`](FatalError)).

    import BackendTask exposing (BackendTask)
    import BackendTask.Custom
    import Json.Encode
    import OptimizedDecoder as Decode

    data : BackendTask FatalError String
    data =
        BackendTask.Custom.run "environmentVariable"
            (Json.Encode.string "EDITOR")
            Decode.string
            |> BackendTask.allowFatal

    -- will resolve to "VIM" if you run `EDITOR=vim elm-pages dev`

```javascript
// custom-backend-task.js

/**
* @param { string } fromElm
* @returns { Promise<string> }
*/
export async function environmentVariable(name) {
    const result = process.env[name];
    if (result) {
      return result;
    } else {
      throw `No environment variable called ${name}

Available:

${Object.keys(process.env).join("\n")}
`;
    }
}
```


## Performance

As with any JavaScript or NodeJS code, avoid doing blocking IO operations. For example, avoid using `fs.readFileSync`, because blocking IO can slow down your elm-pages builds and dev server. `elm-pages` performs all `BackendTask`'s in parallel whenever possible.
So if you do `BackendTask.map2 Tuple.pair myHttpBackendTask myCustomBackendTask`, it will resolve those two in parallel. NodeJS performs best when you take advantage of its ability to do non-blocking I/O (file reads, HTTP requests, etc.). If you use `BackendTask.andThen`,
it will need to resolve them in sequence rather than in parallel, but it's still best to avoid blocking IO operations in your Custom BackendTask definitions.


## Error Handling

There are a few different things that can go wrong when running a custom-backend-task. These possible errors are captured in the `BackendTask.Custom.Error` type.

@docs Error

Any time you throw a JavaScript exception from a BackendTask.Custom definition, it will give you a `CustomBackendTaskException`. It's usually easier to add a `try`/`catch` in your JavaScript code in `custom-backend-task.js`
to handle possible errors, but you can throw a JSON value and handle it in Elm in the `CustomBackendTaskException` call error.


## Decoding JS Date Objects

These decoders are for use with decoding JS values of type `Date`. If you have control over the format, it may be better to
be more explicit with a [Rata Die](https://en.wikipedia.org/wiki/Rata_Die) number value or an ISO-8601 formatted date string instead.
But often JavaScript libraries and core APIs will give you JS Date objects, so this can be useful for working with those.

@docs timeDecoder, dateDecoder

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Date
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import TerminalText
import Time


{-| -}
run :
    String
    -> Encode.Value
    -> Decoder b
    -> BackendTask { fatal : FatalError, recoverable : Error } b
run portName input decoder =
    request
        { body =
            Encode.object
                [ ( "input", input )
                , ( "portName", Encode.string portName )
                ]
                |> BackendTask.Http.jsonBody
        , expect =
            Decode.field "elm-pages-internal-error" Decode.string
                |> Decode.maybe
                |> Decode.andThen
                    (\maybeInternalErrorCode ->
                        case maybeInternalErrorCode of
                            Just errorKind ->
                                --Decode.field "elm-pages-internal-error" Decode.string
                                --    |> Decode.andThen
                                (--\errorKind ->
                                 if errorKind == "CustomBackendTaskNotDefined" then
                                    FatalError.recoverable
                                        { title = "Custom BackendTask Error"
                                        , body =
                                            [ TerminalText.text "Something went wrong in a call to BackendTask.Custom.run. I expected to find a port named `"
                                            , TerminalText.yellow portName
                                            , TerminalText.text "` but I couldn't find it. Is the function exported in your custom-backend-task file?"
                                            ]
                                                |> TerminalText.toString
                                        }
                                        (CustomBackendTaskNotDefined { name = portName })
                                        |> Decode.succeed

                                 else if errorKind == "ExportIsNotFunction" then
                                    Decode.field "error" Decode.string
                                        |> Decode.maybe
                                        |> Decode.map (Maybe.withDefault "")
                                        |> Decode.map
                                            (\incorrectType ->
                                                FatalError.recoverable
                                                    { title = "Custom BackendTask Error"
                                                    , body =
                                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Custom.run. I found an export called `"
                                                        , TerminalText.yellow portName
                                                        , TerminalText.text "` but I expected its type to be function, but instead its type was: "
                                                        , TerminalText.red incorrectType
                                                        ]
                                                            |> TerminalText.toString
                                                    }
                                                    ExportIsNotFunction
                                            )

                                 else if errorKind == "MissingCustomBackendTaskFile" then
                                    FatalError.recoverable
                                        { title = "Custom BackendTask Error"
                                        , body =
                                            [ TerminalText.text "Something went wrong in a call to BackendTask.Custom.run. I couldn't find your custom-backend-task file. Be sure to create a 'custom-backend-task.ts' or 'custom-backend-task.js' file."
                                            ]
                                                |> TerminalText.toString
                                        }
                                        MissingCustomBackendTaskFile
                                        |> Decode.succeed

                                 else if errorKind == "ErrorInCustomBackendTaskFile" then
                                    Decode.field "error" Decode.string
                                        |> Decode.maybe
                                        |> Decode.map (Maybe.withDefault "")
                                        |> Decode.map
                                            (\errorMessage ->
                                                FatalError.recoverable
                                                    { title = "Custom BackendTask Error"
                                                    , body =
                                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Custom.run. I couldn't import the port definitions file, because of this exception:\n\n"
                                                        , TerminalText.red errorMessage
                                                        , TerminalText.text "\n\nAre there syntax errors or exceptions thrown during import?"
                                                        ]
                                                            |> TerminalText.toString
                                                    }
                                                    ErrorInCustomBackendTaskFile
                                            )

                                 else if errorKind == "CustomBackendTaskException" then
                                    Decode.field "error" Decode.value
                                        |> Decode.maybe
                                        |> Decode.map (Maybe.withDefault Encode.null)
                                        |> Decode.map
                                            (\portCallError ->
                                                FatalError.recoverable
                                                    { title = "Custom BackendTask Error"
                                                    , body =
                                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Custom.run. I was able to import the port definitions file, but when running it I encountered this exception:\n\n"
                                                        , TerminalText.red (Encode.encode 2 portCallError)
                                                        , TerminalText.text "\n\nYou could add a `try`/`catch` in your `custom-backend-task` JavaScript code to handle that error."
                                                        ]
                                                            |> TerminalText.toString
                                                    }
                                                    (CustomBackendTaskException portCallError)
                                            )

                                 else if errorKind == "NonJsonException" then
                                    Decode.map2
                                        (\exceptionMessage stackTrace ->
                                            FatalError.recoverable
                                                { title = "Custom BackendTask Error"
                                                , body =
                                                    [ TerminalText.text "Something went wrong in a call to BackendTask.Custom.run. I was able to import the port definitions file, but when running it I encountered this exception:\n\n"
                                                    , TerminalText.red exceptionMessage
                                                    , TerminalText.text ("\n\n" ++ (stackTrace |> Maybe.withDefault "\n"))
                                                    , TerminalText.text "\n\nYou could add a `try`/`catch` in your `custom-backend-task` JavaScript code to handle that error."
                                                    ]
                                                        |> TerminalText.toString
                                                }
                                                (NonJsonException exceptionMessage)
                                        )
                                        (Decode.field "error" Decode.string)
                                        (Decode.field "stack" (Decode.nullable Decode.string))

                                 else
                                    FatalError.recoverable
                                        { title = "Custom BackendTask Error"
                                        , body =
                                            [ TerminalText.text "Something went wrong in a call to BackendTask.Custom.run. I expected to find a port named `"
                                            , TerminalText.yellow portName
                                            , TerminalText.text "`."
                                            ]
                                                |> TerminalText.toString
                                        }
                                        ErrorInCustomBackendTaskFile
                                        |> Decode.succeed
                                )
                                    |> Decode.map Err

                            Nothing ->
                                decoder |> Decode.map Ok
                    )
                |> BackendTask.Http.expectJson
        }
        |> BackendTask.andThen BackendTask.fromResult


{-| -}
type Error
    = Error
    | ErrorInCustomBackendTaskFile
    | MissingCustomBackendTaskFile
    | CustomBackendTaskNotDefined { name : String }
    | CustomBackendTaskException Decode.Value
    | NonJsonException String
    | ExportIsNotFunction
    | DecodeError Decode.Error


{-| -}
timeDecoder : Decoder Time.Posix
timeDecoder =
    Decode.field "__elm-pages-normalized__"
        (Decode.field "kind" Decode.string
            |> Decode.andThen
                (\kind ->
                    if kind == "Date" then
                        Decode.field "value"
                            (Decode.int |> Decode.map Time.millisToPosix)

                    else
                        Decode.fail <| "I was running BackendTask.Custom.timeDecoder and expecting an elm-pages normalized Object with kind \"Date\", but got kind \"" ++ kind ++ "\"."
                )
        )


{-| The same as `timeDecoder`, but it converts the decoded `Time.Posix` value into a `Date` with `Date.fromPosix Time.utc`.

JavaScript `Date` objects don't distinguish between values with only a date vs. values with both a date and a time. So be sure
to use this decoder when you know the semantics represent a date with no associated time (or you're sure you don't care about the time).

-}
dateDecoder : Decoder Date.Date
dateDecoder =
    Decode.field "__elm-pages-normalized__"
        (Decode.field "kind" Decode.string
            |> Decode.andThen
                (\kind ->
                    if kind == "Date" then
                        Decode.field "value"
                            (Decode.int |> Decode.map (Time.millisToPosix >> Date.fromPosix Time.utc))

                    else
                        Decode.fail <| "I was running BackendTask.Custom.dateDecoder and expecting an elm-pages normalized Object with kind \"Date\", but got kind \"" ++ kind ++ "\"."
                )
        )


request :
    { body : BackendTask.Http.Body
    , expect : BackendTask.Http.Expect a
    }
    -> BackendTask { fatal : FatalError, recoverable : Error } a
request { body, expect } =
    -- elm-review: known-unoptimized-recursion
    BackendTask.Http.request
        { url = "elm-pages-internal://port"
        , method = "GET"
        , headers = []
        , body = body
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        expect
        |> BackendTask.onError
            (\error ->
                -- TODO avoid crash here, this should be handled as an internal error
                --request params
                case error.recoverable of
                    BackendTask.Http.BadBody (Just jsonError) _ ->
                        { recoverable = DecodeError jsonError
                        , fatal = error.fatal
                        }
                            |> BackendTask.fail

                    _ ->
                        { recoverable = Error
                        , fatal = error.fatal
                        }
                            |> BackendTask.fail
            )
