module Pages.Parser exposing (AppData, Page, document, imageSrc, normalizedUrl)

import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Mark
import Mark.Error


type alias Page metadata view =
    { metadata : metadata
    , view : view
    }


normalizedUrl : String -> String
normalizedUrl url =
    url
        |> String.split "#"
        |> List.head
        |> Maybe.withDefault ""


type alias AppData metadata =
    { imageAssets : Dict String String
    , routes : List String
    , indexView : List ( List String, metadata )
    }


document :
    Mark.Block metadata
    -> AppData metadata
    -> List (Mark.Block view)
    -> Mark.Document (Page metadata (List view))
document metadata appData blocks =
    Mark.documentWith
        (\meta body ->
            { metadata = meta, view = body }
        )
        -- We have some required metadata that starts our document.
        { metadata = metadata
        , body = Mark.manyOf blocks
        }


imageSrc : Dict String String -> Mark.Block String
imageSrc imageAssets =
    Mark.string
        |> Mark.verify
            (\src ->
                if src |> String.startsWith "http" then
                    Ok src

                else
                    case Dict.get src imageAssets of
                        Just hashedImagePath ->
                            Ok hashedImagePath

                        Nothing ->
                            Err
                                { title = "Could not image `" ++ src ++ "`"
                                , message =
                                    [ "Must be one of\n"
                                    , Dict.keys imageAssets |> String.join "\n"
                                    ]
                                }
            )
