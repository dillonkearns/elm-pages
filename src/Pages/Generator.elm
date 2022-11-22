module Pages.Generator exposing
    ( Generator(..)
    , withCliOptions
    , writeFile
    , log
    , withoutCliOptions
    )

{-|

@docs Generator

@docs simple, withCliOptions


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


type Generator
    = Generator
        ((Maybe { indent : Int, newLines : Bool }
          -> Html Never
          -> String
         )
         -> Program.Config (DataSource ())
        )


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


log : String -> DataSource ()
log message =
    -- TODO implement an internal DataSource resolver for log
    DataSource.succeed ()


withoutCliOptions : DataSource () -> Generator
withoutCliOptions execute =
    Generator
        (\htmlToString ->
            Program.config
                |> Program.add
                    (OptionsParser.build ())
                |> Program.mapConfig
                    (\() ->
                        execute
                    )
        )


withCliOptions : Program.Config cliOptions -> (cliOptions -> DataSource ()) -> Generator
withCliOptions config execute =
    Generator
        (\htmlToString ->
            config
                |> Program.mapConfig execute
        )
