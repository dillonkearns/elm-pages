module Pages.Script exposing
    ( Script(..)
    , withCliOptions, withoutCliOptions
    , writeFile
    , log
    )

{-|

@docs Script

@docs withCliOptions, withoutCliOptions


## File System Utilities

@docs writeFile


## Utilities

@docs log

-}

import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.Internal.Request
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode as Encode


{-| -}
type Script
    = Script
        ((Maybe { indent : Int, newLines : Bool }
          -> Html Never
          -> String
         )
         -> Program.Config (DataSource ())
        )


{-| -}
writeFile : { path : String, body : String } -> DataSource ()
writeFile { path, body } =
    DataSource.Internal.Request.request
        { name = "write-file"
        , body =
            DataSource.Http.jsonBody
                (Encode.object
                    [ ( "path", Encode.string path )
                    , ( "body", Encode.string body )
                    ]
                )
        , expect = DataSource.Http.expectJson (Decode.succeed ())
        }


{-| -}
log : String -> DataSource ()
log message =
    DataSource.Internal.Request.request
        { name = "log"
        , body =
            DataSource.Http.jsonBody
                (Encode.object
                    [ ( "message", Encode.string message )
                    ]
                )
        , expect = DataSource.Http.expectJson (Decode.succeed ())
        }


{-| -}
withoutCliOptions : DataSource () -> Script
withoutCliOptions execute =
    Script
        (\_ ->
            Program.config
                |> Program.add
                    (OptionsParser.build ())
                |> Program.mapConfig
                    (\() ->
                        execute
                    )
        )


{-| -}
withCliOptions : Program.Config cliOptions -> (cliOptions -> DataSource ()) -> Script
withCliOptions config execute =
    Script
        (\_ ->
            config
                |> Program.mapConfig execute
        )
