module Pages.ImagePath exposing (ImagePath, build, external, toString)


type ImagePath key
    = Internal (List String)
    | External String


toString : ImagePath key -> String
toString path =
    case path of
        Internal rawPath ->
            "/"
                ++ (rawPath |> String.join "/")

        External url ->
            url


build : key -> List String -> ImagePath key
build key path =
    Internal path


external : String -> ImagePath key
external url =
    External url
