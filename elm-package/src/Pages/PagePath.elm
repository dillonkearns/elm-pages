module Pages.PagePath exposing (PagePath, build, external, inFolder, toString)


type PagePath key
    = Internal (List String)
    | External String


inFolder : PagePath key -> PagePath key -> Bool
inFolder folder page =
    toString page
        |> String.startsWith (toString folder)


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
