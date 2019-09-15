module Pages.Directory exposing (Directory, WithIndex, WithoutIndex, includes, indexPath, withIndex, withoutIndex)

import Pages.PagePath as PagePath exposing (PagePath)


type WithIndex
    = WithIndex


type WithoutIndex
    = WithoutIndex


type Directory key hasIndex
    = Directory key (List (PagePath key)) (List String)


includes : Directory key hasIndex -> PagePath key -> Bool
includes (Directory key allPagePaths directoryPath) pagePath =
    allPagePaths
        |> List.filter
            (\path ->
                PagePath.toString path
                    |> String.startsWith (toString directoryPath)
            )
        |> List.member pagePath


indexPath : Directory key WithIndex -> PagePath key
indexPath (Directory key allPagePaths directoryPath) =
    PagePath.build key directoryPath


toString : List String -> String
toString rawPath =
    "/"
        ++ (rawPath |> String.join "/")


withIndex : key -> List (PagePath key) -> List String -> Directory key WithIndex
withIndex key allPagePaths path =
    Directory key allPagePaths path


withoutIndex : key -> List (PagePath key) -> List String -> Directory key WithoutIndex
withoutIndex key allPagePaths path =
    Directory key allPagePaths path
