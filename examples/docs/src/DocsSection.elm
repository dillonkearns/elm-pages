module DocsSection exposing (Section, all, codec)

import Codec exposing (Codec)
import DataSource exposing (DataSource)
import DataSource.Glob as Glob


type alias Section =
    { filePath : String
    , order : Int
    , slug : String
    }


codec : Codec (List Section)
codec =
    Codec.object Section
        |> Codec.field "filePath" .filePath Codec.string
        |> Codec.field "order" .order Codec.int
        |> Codec.field "slug" .slug Codec.string
        |> Codec.buildObject
        |> Codec.list


all : DataSource (List Section)
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
