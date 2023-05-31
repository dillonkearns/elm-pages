module DocsSection exposing (Section, all)

import BackendTask exposing (BackendTask)
import BackendTask.Glob as Glob
import BuildError exposing (BuildError)


type alias Section =
    { filePath : String
    , order : Int
    , slug : String
    }


all : BackendTask error (List Section)
all =
    Glob.succeed Section
        |> Glob.captureFilePath
        |> Glob.match (Glob.literal "content/docs/")
        |> Glob.capture Glob.int
        |> Glob.match (Glob.literal "-")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
        |> Glob.toBackendTask
        |> BackendTask.map
            (\sections ->
                sections
                    |> List.sortBy .order
            )
