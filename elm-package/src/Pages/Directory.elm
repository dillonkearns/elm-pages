module Pages.Directory exposing (Directory, WithIndex, WithoutIndex, includes, indexPath, withIndex, withoutIndex)

import Pages.PagePath as PagePath exposing (PagePath)


type WithIndex
    = WithIndex


type WithoutIndex
    = WithoutIndex


type Directory key hasIndex
    = Directory (List (PagePath key)) (List String)


includes : Directory key hasIndex -> PagePath key -> Bool
includes (Directory allPagePaths directoryPath) pagePath =
    allPagePaths
        |> List.filter
            (\path ->
                PagePath.toString path
                    |> String.startsWith (toString directoryPath)
            )
        |> List.member pagePath


indexPath : Directory key WithIndex -> String
indexPath (Directory allPagePaths directoryPath) =
    toString directoryPath


toString : List String -> String
toString rawPath =
    "/"
        ++ (rawPath |> String.join "/")


build : hasIndex -> key -> List (PagePath key) -> List String -> Directory key hasIndex
build hasIndex key allPagePaths path =
    Directory allPagePaths path


withIndex : key -> List (PagePath key) -> List String -> Directory key WithIndex
withIndex key allPagePaths path =
    Directory allPagePaths path


withoutIndex : key -> List (PagePath key) -> List String -> Directory key WithoutIndex
withoutIndex key allPagePaths path =
    Directory allPagePaths path
