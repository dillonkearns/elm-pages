module Shiki exposing (Highlighted, decoder, view)

import Html exposing (Html)
import Html.Attributes as Attr exposing (class)
import Html.Lazy
import OptimizedDecoder as Decode exposing (Decoder)


type alias ShikiToken =
    { content : String
    , color : String
    , fontStyle : Maybe ( String, String )
    }


type alias Highlighted =
    { lines : List (List ShikiToken)
    , bg : String
    }


decoder : Decoder Highlighted
decoder =
    Decode.map2 Highlighted
        (Decode.field "tokens" (Decode.list (Decode.list shikiTokenDecoder)))
        (Decode.field "bg" Decode.string)


shikiTokenDecoder : Decode.Decoder ShikiToken
shikiTokenDecoder =
    Decode.map3 ShikiToken
        (Decode.field "content" Decode.string)
        (Decode.field "color" Decode.string)
        (Decode.field "fontStyle" fontStyleDecoder)


fontStyleDecoder : Decoder (Maybe ( String, String ))
fontStyleDecoder =
    Decode.int
        |> Decode.map
            (\styleNumber ->
                case styleNumber of
                    1 ->
                        Just ( "font-style", "italic" )

                    2 ->
                        Just ( "font-style", "bold" )

                    4 ->
                        Just ( "font-style", "underline" )

                    _ ->
                        Nothing
            )


{-| <https://github.com/shikijs/shiki/blob/2a31dc50f4fbdb9a63990ccd15e08cccc9c1566a/packages/shiki/src/renderer.ts#L16>
-}
view : List (Html.Attribute msg) -> Highlighted -> Html msg
view attrs highlighted =
    highlighted.lines
        |> List.indexedMap
            (\lineIndex line ->
                let
                    isLastLine =
                        List.length highlighted.lines == (lineIndex + 1)
                in
                Html.span [ class "line" ]
                    ((line
                        |> List.map
                            (\token ->
                                Html.span
                                    [ Attr.style "color" token.color
                                    , token.fontStyle
                                        |> Maybe.map
                                            (\( key, value ) ->
                                                Attr.style key value
                                            )
                                        |> Maybe.withDefault (Attr.title "")
                                    ]
                                    [ Html.text token.content ]
                            )
                     )
                        ++ [ if isLastLine then
                                Html.text ""

                             else
                                Html.text "\n"
                           ]
                    )
            )
        |> Html.code []
        |> List.singleton
        |> Html.pre
            ([ Attr.style "background-color" highlighted.bg
             , Attr.style "white-space" "pre-wrap"
             , Attr.style "overflow-wrap" "break-word"
             ]
                ++ attrs
            )
