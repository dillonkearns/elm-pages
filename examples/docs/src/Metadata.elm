module Metadata exposing (ArticleMetadata, DocMetadata, Metadata(..), PageMetadata, metadata)

import Dict exposing (Dict)
import Element exposing (Element)
import Element.Font as Font
import Mark
import Pages.Parser


type Metadata msg
    = Page PageMetadata
    | Article (ArticleMetadata msg)
    | Doc DocMetadata


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }


type alias ArticleMetadata msg =
    { title : { styled : List (Element msg), raw : String }
    , description : { styled : List (Element msg), raw : String }
    }


metadata : Dict String String -> Mark.Block (Metadata msg)
metadata imageAssets =
    Mark.oneOf
        [ Mark.record "Article"
            (\title description ->
                Article
                    { title = title
                    , description = description
                    }
            )
            |> Mark.field "title"
                (Mark.map
                    gather
                    titleText
                )
            |> Mark.field "description"
                (Mark.map
                    gather
                    titleText
                )
            |> Mark.toBlock
        , Mark.record "Page"
            (\title ->
                Page
                    { title = title }
            )
            |> Mark.field "title" Mark.string
            |> Mark.toBlock
        , Mark.record "Doc"
            (\title ->
                Doc
                    { title = title }
            )
            |> Mark.field "title" Mark.string
            |> Mark.toBlock
        ]


gather : List { styled : Element msg, raw : String } -> { styled : List (Element msg), raw : String }
gather myList =
    let
        styled =
            myList
                |> List.map .styled

        raw =
            myList
                |> List.map .raw
                |> String.join " "
    in
    { styled = styled, raw = raw }


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
