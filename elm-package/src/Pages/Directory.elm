module Pages.Directory exposing (Directory, build, includes)

import Pages.PagePath exposing (PagePath)


type Directory key
    = Directory (List (PagePath key)) (List String)


includes : Directory key -> PagePath key -> Bool
includes pathKeyDirectory pathKeyPagePath =
    False


toString : Directory key -> String
toString path =
    case path of
        Directory allPagePaths rawPath ->
            "/"
                ++ (rawPath |> String.join "/")


build : key -> List (PagePath key) -> List String -> Directory key
build key allPagePaths path =
    Directory allPagePaths path
