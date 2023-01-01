module DataSource.Port exposing
    ( get
    , Error(..)
    )

{-|

@docs get

@docs Error

-}

import DataSource
import DataSource.Http
import DataSource.Internal.Request
import Exception exposing (Catchable)
import Json.Decode exposing (Decoder)
import Json.Encode as Encode
import TerminalText


{-| In a vanilla Elm application, ports let you either send or receive JSON data between your Elm application and the JavaScript context in the user's browser at runtime.

With `DataSource.Port`, you send and receive JSON to JavaScript running in NodeJS during build-time. This means that you can call shell scripts, or run NPM packages that are installed, or anything else you could do with NodeJS.

A `DataSource.Port` will call an async JavaScript function with the given name. The function receives the input JSON value, and the Decoder is used to decode the return value of the async function.

Here is the Elm code and corresponding JavaScript definition for getting an environment variable (or a build error if it isn't found).

    import DataSource exposing (DataSource)
    import DataSource.Port
    import Json.Encode
    import OptimizedDecoder as Decode

    data : DataSource String
    data =
        DataSource.Port.get "environmentVariable"
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

Any time you throw an exception from a DataSource.Port definition, it will result in a build error in your `elm-pages build` or dev server. In the example above, if the environment variable
is not found it will result in a build failure. Notice that the NPM package `kleur` is being used in this example to add color to the output for that build error. You can use any tool you
prefer to add ANSI color codes within the error string in an exception and it will show up with color output in the build output and dev server.


## Performance

As with any JavaScript or NodeJS code, avoid doing blocking IO operations. For example, avoid using `fs.readFileSync`, because blocking IO can slow down your elm-pages builds and dev server.

-}
get : String -> Encode.Value -> Decoder b -> DataSource.DataSource (Catchable Error) b
get portName input decoder =
    DataSource.Internal.Request.request
        { name = "port"
        , body =
            Encode.object
                [ ( "input", input )
                , ( "portName", Encode.string portName )
                ]
                |> DataSource.Http.jsonBody
        , expect =
            decoder
                |> DataSource.Http.expectJson
        }
        |> DataSource.onError
            (\_ ->
                DataSource.fail
                    (Exception.Catchable Error
                        { title = "Port Error"
                        , body =
                            [ TerminalText.text "Something went wrong in a call to DataSource.Port.get."
                            ]
                        }
                    )
            )


{-| -}
type Error
    = -- TODO include additional context about error or better name to reflect the error state
      Error
