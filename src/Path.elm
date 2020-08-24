module Path exposing (Path, fromList, fromPath, toList, toRelative)


fromPath : { url | path : String } -> Path
fromPath { path } =
    path
        |> normalizePath
        |> RelativePath


toList : Path -> List String
toList (RelativePath relativePath) =
    relativePath
        |> dropTrailing
        |> String.split "/"


dropTrailing : String -> String
dropTrailing string =
    if string |> String.endsWith "/" then
        string |> String.dropRight 1

    else
        string


type Path
    = RelativePath String


fromList list =
    list
        |> String.join "/"
        |> RelativePath


toRelative (RelativePath path) =
    path


normalizePath : String -> String
normalizePath pathString =
    let
        hasPrefix =
            String.startsWith "/" pathString

        hasSuffix =
            String.endsWith "/" pathString
    in
    if pathString == "" then
        pathString

    else
        String.concat
            [ if hasPrefix then
                String.dropLeft 1 pathString

              else
                pathString
            , if hasSuffix then
                ""

              else
                "/"
            ]
