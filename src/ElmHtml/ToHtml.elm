module ElmHtml.ToHtml exposing (toHtml, factsToAttributes)

{-| This module is particularly useful for putting parsed Html into Elm.Html at runtime.
Estentially allowing the user to use tools like html-to-elm on their code.

@docs toHtml, factsToAttributes

-}

import Dict exposing (Dict)
import ElmHtml.InternalTypes exposing (..)
import Html
import Html.Attributes
import Html.Events
import Json.Decode
import Json.Encode
import String


{-| Turns ElmHtml into normal Elm Html
-}
toHtml : ElmHtml msg -> Html.Html msg
toHtml elmHtml =
    case elmHtml of
        TextTag text ->
            Html.text text.text

        NodeEntry { tag, children, facts } ->
            Html.node tag [] (List.map toHtml children)

        CustomNode record ->
            --let
            --    _ =
            --        Debug.log "Custom node is not supported" ""
            --in
            Html.text ""

        MarkdownNode record ->
            --let
            --    _ =
            --        Debug.log "Markdown node is not supported" ""
            --in
            Html.text ""

        NoOp ->
            Html.text ""


stylesToAttribute : Dict String String -> List (Html.Attribute msg)
stylesToAttribute =
    Dict.toList
        >> (List.map (\(k, v) -> Html.Attributes.style k v))


eventsToAttributes : Dict String (Json.Decode.Decoder msg) -> List (Html.Attribute msg)
eventsToAttributes =
    Dict.toList
        >> List.map (\( x, y ) -> Html.Events.on x y)


stringAttributesToAttributes : Dict String String -> List (Html.Attribute msg)
stringAttributesToAttributes =
    Dict.toList
        >> List.map (\( x, y ) -> Html.Attributes.attribute x y)


boolAttributesToAttributes : Dict String Bool -> List (Html.Attribute msg)
boolAttributesToAttributes =
    Dict.toList
        >> List.map (\( x, y ) -> Html.Attributes.property x (Json.Encode.bool y))


{-| Turns a fact record into a list of attributes
-}
factsToAttributes : Facts msg -> List (Html.Attribute msg)
factsToAttributes facts =
    List.concat
        [ stylesToAttribute facts.styles
        , eventsToAttributes facts.events
        , stringAttributesToAttributes facts.stringAttributes
        , boolAttributesToAttributes facts.boolAttributes
        ]
