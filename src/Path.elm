module Path exposing (..)


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
