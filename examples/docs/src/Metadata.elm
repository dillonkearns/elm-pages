module Metadata exposing (DocMetadata, Metadata(..), PageMetadata)

import Dict exposing (Dict)
import Element exposing (Element)
import Element.Font as Font


type Metadata msg
    = Page PageMetadata
    | Article { author : String, title : String }
    | Doc DocMetadata


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }


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
