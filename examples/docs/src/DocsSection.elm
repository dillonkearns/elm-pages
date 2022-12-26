module DocsSection exposing (Section, all)

import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import DataSource.Glob as Glob


type alias Section =
    { filePath : String
    , order : Int
    , slug : String
    }


all : DataSource BuildError (List Section)
all =
    Glob.succeed Section
        |> Glob.captureFilePath
        |> Glob.match (Glob.literal "content/docs/")
        |> Glob.capture Glob.int
        |> Glob.match (Glob.literal "-")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
        |> Glob.toDataSource
        |> DataSource.map
            (\sections ->
                sections
                    |> List.sortBy .order
            )
