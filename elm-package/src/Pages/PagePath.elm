module Pages.PagePath exposing (PagePath, build, external, toString)


type PagePath key
    = Internal (List String)
    | External String


toString : PagePath key -> String
toString path =
    case path of
        Internal rawPath ->
            "/"
                ++ (rawPath |> String.join "/")

        External url ->
            url


external : String -> PagePath key
external url =
    External url


build : key -> List String -> PagePath key
build key path =
    Internal path
