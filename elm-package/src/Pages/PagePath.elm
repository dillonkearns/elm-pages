module Pages.PagePath exposing (PagePath, build, toString)


type PagePath key
    = PagePath (List String)


toString : PagePath key -> String
toString (PagePath rawPath) =
    "/"
        ++ (rawPath |> String.join "/")


build : key -> List String -> PagePath key
build key path =
    PagePath path
