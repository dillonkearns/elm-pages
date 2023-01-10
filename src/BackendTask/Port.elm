module BackendTask.Port exposing
    ( get
    , Error(..)
    )

{-|

@docs get

@docs Error

-}

import BackendTask
import BackendTask.Http
import BackendTask.Internal.Request
import Exception exposing (Exception)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import TerminalText


{-| In a vanilla Elm application, ports let you either send or receive JSON data between your Elm application and the JavaScript context in the user's browser at runtime.

With `BackendTask.Port`, you send and receive JSON to JavaScript running in NodeJS during build-time. This means that you can call shell scripts, or run NPM packages that are installed, or anything else you could do with NodeJS.

A `BackendTask.Port` will call an async JavaScript function with the given name. The function receives the input JSON value, and the Decoder is used to decode the return value of the async function.

Here is the Elm code and corresponding JavaScript definition for getting an environment variable (or a build error if it isn't found).

    import BackendTask exposing (BackendTask)
    import BackendTask.Port
    import Json.Encode
    import OptimizedDecoder as Decode

    data : BackendTask String
    data =
        BackendTask.Port.get "environmentVariable"
            (Json.Encode.string "EDITOR")
            Decode.string

    -- will resolve to "VIM" if you run `EDITOR=vim elm-pages dev`

```javascript
const kleur = require("kleur");


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
        throw `No environment variable called ${kleur
          .yellow()
          .underline(name)}\n\nAvailable:\n\n${Object.keys(process.env).join(
          "\n"
        )}`;
      }
    },
  }
```


## Error Handling

`port-data-source.js`

Any time you throw an exception from a BackendTask.Port definition, it will result in a build error in your `elm-pages build` or dev server. In the example above, if the environment variable
is not found it will result in a build failure. Notice that the NPM package `kleur` is being used in this example to add color to the output for that build error. You can use any tool you
prefer to add ANSI color codes within the error string in an exception and it will show up with color output in the build output and dev server.


## Performance

As with any JavaScript or NodeJS code, avoid doing blocking IO operations. For example, avoid using `fs.readFileSync`, because blocking IO can slow down your elm-pages builds and dev server.

-}
get : String -> Encode.Value -> Decoder b -> BackendTask.BackendTask (Exception Error) b
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
                                Exception.Exception (PortNotDefined { name = portName })
                                    { title = "Port Error"
                                    , body =
                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I expected to find a port named `"
                                        , TerminalText.yellow portName
                                        , TerminalText.text "` but I couldn't find it. Is the function exported in your port-data-source file?"
                                        ]
                                            |> TerminalText.toString
                                    }
                                    |> Decode.succeed

                            else if errorKind == "ExportIsNotFunction" then
                                Decode.field "error" Decode.string
                                    |> Decode.maybe
                                    |> Decode.map (Maybe.withDefault "")
                                    |> Decode.map
                                        (\incorrectPortType ->
                                            Exception.Exception ExportIsNotFunction
                                                { title = "Port Error"
                                                , body =
                                                    [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I found an export called `"
                                                    , TerminalText.yellow portName
                                                    , TerminalText.text "` but I expected its type to be function, but instead its type was: "
                                                    , TerminalText.red incorrectPortType
                                                    ]
                                                        |> TerminalText.toString
                                                }
                                        )

                            else if errorKind == "MissingPortsFile" then
                                Exception.Exception MissingPortsFile
                                    { title = "Port Error"
                                    , body =
                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I couldn't find your port-data-source file. Be sure to create a 'port-data-source.ts' or 'port-data-source.js' file."
                                        ]
                                            |> TerminalText.toString
                                    }
                                    |> Decode.succeed

                            else if errorKind == "ErrorInPortsFile" then
                                Decode.field "error" Decode.string
                                    |> Decode.maybe
                                    |> Decode.map (Maybe.withDefault "")
                                    |> Decode.map
                                        (\errorMessage ->
                                            Exception.Exception
                                                ErrorInPortsFile
                                                { title = "Port Error"
                                                , body =
                                                    [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I couldn't import the port definitions file, because of this exception:\n\n"
                                                    , TerminalText.red errorMessage
                                                    , TerminalText.text "\n\nAre there syntax errors or exceptions thrown during import?"
                                                    ]
                                                        |> TerminalText.toString
                                                }
                                        )

                            else if errorKind == "PortCallError" then
                                Decode.field "error" Decode.value
                                    |> Decode.maybe
                                    |> Decode.map (Maybe.withDefault Encode.null)
                                    |> Decode.map
                                        (\portCallError ->
                                            Exception.Exception
                                                (PortCallError portCallError)
                                                { title = "Port Error"
                                                , body =
                                                    [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I couldn't import the port definitions file, because of this exception:\n\n"
                                                    , TerminalText.red (Encode.encode 2 portCallError)
                                                    , TerminalText.text "\n\nAre there syntax errors or exceptions thrown during import?"
                                                    ]
                                                        |> TerminalText.toString
                                                }
                                        )

                            else
                                Exception.Exception ErrorInPortsFile
                                    { title = "Port Error"
                                    , body =
                                        [ TerminalText.text "Something went wrong in a call to BackendTask.Port.get. I expected to find a port named `"
                                        , TerminalText.yellow portName
                                        , TerminalText.text "`."
                                        ]
                                            |> TerminalText.toString
                                    }
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
    | PortCallError Decode.Value
    | ExportIsNotFunction
