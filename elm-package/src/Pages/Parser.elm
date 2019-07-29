module Pages.Parser exposing (AppData, PageOrPost, document, imageSrc, normalizedUrl)

import Dict exposing (Dict)
import Element exposing (Element)
import Element.Border
import Element.Font as Font
import Element.Region
import Html exposing (Html)
import Html.Attributes as Attr
import Mark
import Mark.Error


type alias PageOrPost metadata view =
    { metadata : metadata
    , view : List view
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
    -> Mark.Document (PageOrPost metadata view)
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


titleText : Mark.Block (List { styled : Element msg, raw : String })
titleText =
    Mark.textWith
        { view =
            \styles string ->
                { styled = viewText styles string
                , raw = string
                }
        , replacements = Mark.commonReplacements
        , inlines = []
        }


viewText : { a | bold : Bool, italic : Bool, strike : Bool } -> String -> Element msg
viewText styles string =
    Element.el (stylesFor styles) (Element.text string)


stylesFor : { a | bold : Bool, italic : Bool, strike : Bool } -> List (Element.Attribute b)
stylesFor styles =
    [ if styles.bold then
        Just Font.bold

      else
        Nothing
    , if styles.italic then
        Just Font.italic

      else
        Nothing
    , if styles.strike then
        Just Font.strike

      else
        Nothing
    ]
        |> List.filterMap identity


gather : List { styled : Element msg, raw : String } -> { styled : Element msg, raw : String }
gather myList =
    let
        styled =
            myList
                |> List.map .styled
                |> Element.paragraph []

        raw =
            myList
                |> List.map .raw
                |> String.join " "
    in
    { styled = styled, raw = raw }
