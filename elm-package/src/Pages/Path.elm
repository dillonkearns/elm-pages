module Pages.Path exposing (Path(..), ResourceType(..), buildPath, toString)


type ResourceType
    = Image
    | Page


type Path key
    = Path ResourceType (List String)


toString : Path key -> String
toString (Path resourceType rawPath) =
    "/"
        ++ (rawPath
                |> String.join "/"
           )


buildPath : ResourceType -> key -> List String -> Path key
buildPath resourceType key path =
    Path resourceType path
