module BackendTask.Port exposing
    ( get
    , Error(..)
    )

{-| In a vanilla Elm application, ports let you either send or receive JSON data between your Elm application and the JavaScript context in the user's browser at runtime.

With `BackendTask.Port`, you send and receive JSON to JavaScript running in NodeJS. As with any `BackendTask`, Port BackendTask's are either run at build-time (for pre-rendered routes) or at request-time (for server-rendered routes). See [`BackendTask`](BackendTask) for more about the
lifecycle of `BackendTask`'s.

This means that you can call shell scripts, run NPM packages that are installed, or anything else you could do with NodeJS to perform custom side-effects, get some data, or both.

A `BackendTask.Port` will call an async JavaScript function with the given name from the definition in a file called `port-data-source.js` in your project's root directory. The function receives the input JSON value, and the Decoder is used to decode the return value of the async function.

@docs get

Here is the Elm code and corresponding JavaScript definition for getting an environment variable (or an `FatalError BackendTask.Port.Error` if it isn't found). In this example,
we're using `BackendTask.allowFatal` to let the framework treat that as an unexpected exception, but we could also handle the possible failures of the `FatalError` (see [`FatalError`](FatalError)).

    import BackendTask exposing (BackendTask)
    import BackendTask.Port
    import Json.Encode
    import OptimizedDecoder as Decode

    data : BackendTask FatalError String
    data =
        BackendTask.Port.get "environmentVariable"
            (Json.Encode.string "EDITOR")
            Decode.string
            |> BackendTask.allowFatal

    -- will resolve to "VIM" if you run `EDITOR=vim elm-pages dev`

```javascript
// port-data-source.js

module.exports =
  /**
   * @param { unknown } fromElm
   * @returns { Promise<unknown> }
   */
  {
    environmentVariable: async function (name) {
      const result = process.env[name];
      if (result) {
        return result;
      } else {
        throw `No environment variable called ${name}

Available:

${Object.keys(process.env).join("\n")}
`;
      }
    },
  }
```


## Performance

As with any JavaScript or NodeJS code, avoid doing blocking IO operations. For example, avoid using `fs.readFileSync`, because blocking IO can slow down your elm-pages builds and dev server. `elm-pages` performances all `BackendTask`'s in parallel whenever possible.
So if you do `BackendTask.map2 Tuple.pair myHttpBackendTask myPortBackendTask`, it will resolve those two in parallel. NodeJS performs best when you take advantage of its ability to do non-blocking I/O (file reads, HTTP requests, etc.). If you use `BackendTask.andThen`,
it will need to resolve them in sequence rather than in parallel, but it's still best to avoid blocking IO operations in your BackendTask Port definitions.


## Error Handling

There are a few different things that can go wrong when running a port-data-source. These possible errors are captured in the `BackendTask.Port.Error` type.

@docs Error

Any time you throw a JavaScript exception from a BackendTask.Port definition, it will give you a `PortCallException`. It's usually easier to add a `try`/`catch` in your JavaScript code in `port-data-source.js`
to handle possible errors, but you can throw a JSON value and handle it in Elm in the `PortCallException` call error.

-}

import BackendTask
import BackendTask.Http
import BackendTask.Internal.Request
import FatalError exposing (FatalError, Recoverable)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import TerminalText


{-| -}
get :
    String
    -> Encode.Value
    -> Decoder b
    -> BackendTask.BackendTask { fatal : FatalError, recoverable : Error } b
get portName input decoder =
    BackendTask.Internal.Request.request
        { name = "port"
        , body =
            Encode.object
                [ ( "input", input )
                , ( "portName", Encode.string portName )
                ]
                |> BackendTask.Http.jsonBody
        , expect =
            Decode.oneOf
                [ Decode.field "elm-pages-internal-error" Decode.string
                    |> Decode.andThen
                        (\errorKind ->
                            if errorKind == "PortNotDefined" then
                                { fatal =
                                    { title = "Port Error"
                                    , body =
                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I expected to find a port named `"
                                        , TerminalText.yellow portName
                                        , TerminalText.text "` but I couldn't find it. Is the function exported in your port-data-source file?"
                                        ]
                                            |> TerminalText.toString
                                    }
                                , recoverable = PortNotDefined { name = portName }
                                }
                                    |> Decode.succeed

                            else if errorKind == "ExportIsNotFunction" then
                                Decode.field "error" Decode.string
                                    |> Decode.maybe
                                    |> Decode.map (Maybe.withDefault "")
                                    |> Decode.map
                                        (\incorrectPortType ->
                                            FatalError.Recoverable
                                                { title = "Port Error"
                                                , body =
                                                    [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I found an export called `"
                                                    , TerminalText.yellow portName
                                                    , TerminalText.text "` but I expected its type to be function, but instead its type was: "
                                                    , TerminalText.red incorrectPortType
                                                    ]
                                                        |> TerminalText.toString
                                                }
                                                ExportIsNotFunction
                                        )

                            else if errorKind == "MissingPortsFile" then
                                FatalError.Recoverable
                                    { title = "Port Error"
                                    , body =
                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I couldn't find your port-data-source file. Be sure to create a 'port-data-source.ts' or 'port-data-source.js' file."
                                        ]
                                            |> TerminalText.toString
                                    }
                                    MissingPortsFile
                                    |> Decode.succeed

                            else if errorKind == "ErrorInPortsFile" then
                                Decode.field "error" Decode.string
                                    |> Decode.maybe
                                    |> Decode.map (Maybe.withDefault "")
                                    |> Decode.map
                                        (\errorMessage ->
                                            FatalError.Recoverable
                                                { title = "Port Error"
                                                , body =
                                                    [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I couldn't import the port definitions file, because of this exception:\n\n"
                                                    , TerminalText.red errorMessage
                                                    , TerminalText.text "\n\nAre there syntax errors or exceptions thrown during import?"
                                                    ]
                                                        |> TerminalText.toString
                                                }
                                                ErrorInPortsFile
                                        )

                            else if errorKind == "PortCallException" then
                                Decode.field "error" Decode.value
                                    |> Decode.maybe
                                    |> Decode.map (Maybe.withDefault Encode.null)
                                    |> Decode.map
                                        (\portCallError ->
                                            FatalError.Recoverable
                                                { title = "Port Error"
                                                , body =
                                                    [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I was able to import the port definitions file, but when running it I encountered this exception:\n\n"
                                                    , TerminalText.red (Encode.encode 2 portCallError)
                                                    , TerminalText.text "\n\nYou could add a `try`/`catch` in your `port-data-source` JavaScript code to handle that error."
                                                    ]
                                                        |> TerminalText.toString
                                                }
                                                (PortCallException portCallError)
                                        )

                            else
                                FatalError.Recoverable
                                    { title = "Port Error"
                                    , body =
                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I expected to find a port named `"
                                        , TerminalText.yellow portName
                                        , TerminalText.text "`."
                                        ]
                                            |> TerminalText.toString
                                    }
                                    ErrorInPortsFile
                                    |> Decode.succeed
                        )
                    |> Decode.map Err
                , decoder |> Decode.map Ok
                ]
                |> BackendTask.Http.expectJson
        }
        |> BackendTask.andThen BackendTask.fromResult


{-| -}
type Error
    = Error
    | ErrorInPortsFile
    | MissingPortsFile
    | PortNotDefined { name : String }
    | PortCallException Decode.Value
    | ExportIsNotFunction
