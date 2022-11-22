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
import Html exposing (Html)


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
    -- TODO implement an internal DataSource resolver for writeFile
    DataSource.succeed ()


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
