module Pages.Path exposing (Path(..), ToImage, ToPage, buildImage, buildPage, toString)


type ToImage
    = ToImage


type ToPage
    = ToPage


type Path key resource
    = Path (List String)


toString : Path key resource -> String
toString (Path rawPath) =
    "/"
        ++ (rawPath
                |> String.join "/"
           )


buildImage : key -> List String -> Path key ToImage
buildImage key path =
    Path path


buildPage : key -> List String -> Path key ToPage
buildPage key path =
    Path path
