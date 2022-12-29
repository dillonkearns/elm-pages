module Pages.Script exposing
    ( Script
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
import Exception exposing (Catchable, Throwable)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.Script


{-| -}
type alias Script =
    Pages.Internal.Script.Script


type Error
    = --TODO make more descriptive
      FileWriteError


{-| -}
writeFile : { path : String, body : String } -> DataSource (Catchable Error) ()
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
        , expect =
            -- TODO decode possible error details here
            DataSource.Http.expectJson (Decode.succeed ())
        }


{-| -}
log : String -> DataSource error ()
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
withoutCliOptions : DataSource Throwable () -> Script
withoutCliOptions execute =
    Pages.Internal.Script.Script
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
withCliOptions : Program.Config cliOptions -> (cliOptions -> DataSource Throwable ()) -> Script
withCliOptions config execute =
    Pages.Internal.Script.Script
        (\_ ->
            config
                |> Program.mapConfig execute
        )
