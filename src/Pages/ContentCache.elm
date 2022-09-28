module Pages.ContentCache exposing
    ( Path
    , pathForUrl
    )

import Pages.Internal.String as String
import Url exposing (Url)


type alias Path =
    List String


pathForUrl : { currentUrl : Url, basePath : List String } -> Path
pathForUrl { currentUrl, basePath } =
    currentUrl.path
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")
        |> List.drop (List.length basePath)
