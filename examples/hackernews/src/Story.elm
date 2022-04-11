module Story exposing (..)

import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Route


type alias Story =
    { title : String
    , points : Maybe Int
    , user : Maybe String
    , url : Maybe String
    , domain : String
    , time_ago : String
    , comments_count : Int
    , type_ : String
    , id : Int
    }


view : Story -> Html msg
view story =
    Html.li
        [ Attr.class "news-item"
        ]
        [ Html.span
            [ Attr.class "score"
            ]
            [ Html.text
                (story.points
                    |> Maybe.map String.fromInt
                    |> Maybe.withDefault ""
                )
            ]
        , Html.span
            [ Attr.class "title"
            ]
            (case ( story.url, story.url |> Maybe.withDefault "" |> String.startsWith "item?id=" ) of
                ( Just url, False ) ->
                    [ Html.a
                        [ Attr.href url
                        , Attr.target "_blank"
                        , Attr.rel "noreferrer"
                        ]
                        [ Html.text story.title ]
                    , domainView story.domain
                    ]

                ( Nothing, _ ) ->
                    [ Route.Stories__Id_ { id = String.fromInt story.id }
                        |> Route.link
                            [-- TODO decode into custom type here? --Attr.href ("/item/" ++ story.id)
                            ]
                            [ Html.text story.title ]
                    ]

                _ ->
                    [ Html.text story.title ]
            )
        , Html.br []
            []
        , Html.span
            [ Attr.class "meta"
            ]
            (if story.type_ == "job" then
                [ Route.Stories__Id_ { id = String.fromInt story.id }
                    |> Route.link
                        []
                        [ Html.text story.time_ago
                        ]
                ]

             else
                [ Html.text "by "
                , Html.a [ Attr.href "TODO user page link" ]
                    [ story.user |> Maybe.withDefault "" |> Html.text
                    ]
                , Html.text (" " ++ story.time_ago ++ " | ")
                , Route.Stories__Id_ { id = String.fromInt story.id }
                    |> Route.link
                        []
                        [ if story.comments_count > 0 then
                            Html.text (String.fromInt story.comments_count ++ " comments")

                          else
                            Html.text "discuss"
                        ]
                ]
            )
        , if story.type_ /= "link" then
            Html.span
                [ Attr.class "label"
                ]
                [ Html.text <| " " ++ story.type_ ]

          else
            Html.text ""
        ]


domainView : String -> Html msg
domainView domain =
    Html.span
        [ Attr.class "host"
        ]
        [ Html.text <|
            if String.isEmpty domain then
                ""

            else
                "(" ++ domain ++ ")"
        ]


decoder : Decoder Story
decoder =
    Json.Decode.succeed Story
        |> required "title" Json.Decode.string
        |> required "points" (Json.Decode.nullable Json.Decode.int)
        |> required "user" (Json.Decode.nullable Json.Decode.string)
        |> required "url" (Json.Decode.nullable Json.Decode.string)
        |> optional "domain" Json.Decode.string ""
        |> required "time_ago" Json.Decode.string
        |> required "comments_count" Json.Decode.int
        |> required "type" Json.Decode.string
        |> required "id" Json.Decode.int
