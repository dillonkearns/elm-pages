module DocsSection exposing (Section, all)

import DataSource exposing (DataSource)
import DataSource.Glob as Glob


type alias Section =
    { filePath : String
    , order : Int
    , slug : String
    }


all : DataSource (List Section)
all =
    Glob.succeed Section
        |> Glob.capture Glob.fullFilePath
        |> Glob.ignore (Glob.literal "content/docs/")
        |> Glob.capture Glob.int
        |> Glob.ignore (Glob.literal "-")
        |> Glob.capture Glob.wildcard
        |> Glob.ignore (Glob.literal ".md")
        |> Glob.toDataSource
        |> DataSource.map
            (\sections ->
                sections
                    |> List.sortBy .order
            )
