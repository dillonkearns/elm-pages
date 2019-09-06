module Pages.Path exposing (Path(..), ResourceType(..), buildPath)


type ResourceType
    = Image
    | Page


type Path key
    = Path ResourceType (List String)


buildPath : ResourceType -> key -> List String -> Path key
buildPath resourceType key path =
    Path resourceType path
