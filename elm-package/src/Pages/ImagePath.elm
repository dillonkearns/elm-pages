module Pages.ImagePath exposing (ImagePath, build, toString)


type ImagePath key
    = ImagePath (List String)


toString : ImagePath key -> String
toString (ImagePath rawPath) =
    "/"
        ++ (rawPath |> String.join "/")


build : key -> List String -> ImagePath key
build key path =
    ImagePath path
