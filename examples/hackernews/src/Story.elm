module Story exposing (..)

import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (hardcoded, optional, required)
import Route


type alias StoryRecord =
    { points : Int
    , user : String
    , type_ : String
    }


type alias Common =
    { title : String
    , url : String
    , domain : String
    , time_ago : String
    , comments_count : Int
    , id : Int
    }


type Item
    = Item Common Entry


type Entry
    = Story StoryRecord
    | Job


view : Item -> Html msg
view (Item story entry) =
    Html.li
        [ Attr.class "news-item"
        ]
        [ Html.span
            [ Attr.class "score"
            ]
            [ case entry of
                Story { points } ->
                    Html.text (String.fromInt points)

                _ ->
                    Html.text ""
            ]
        , Html.span
            [ Attr.class "title"
            ]
            (case story.url |> String.startsWith "item?id=" of
                False ->
                    [ Html.a
                        [ Attr.href story.url
                        , Attr.target "_blank"
                        , Attr.rel "noreferrer"
                        ]
                        [ Html.text story.title ]
                    , Html.text " "
                    , domainView story.domain
                    ]

                _ ->
                    [ Route.Stories__Id_ { id = String.fromInt story.id }
                        |> Route.link
                            [-- TODO decode into custom type here? --Attr.href ("/item/" ++ story.id)
                            ]
                            [ Html.text story.title ]
                    ]
            )
        , Html.br []
            []
        , Html.span
            [ Attr.class "meta"
            ]
            (case entry of
                Job ->
                    [ Route.Stories__Id_ { id = String.fromInt story.id }
                        |> Route.link
                            []
                            [ Html.text story.time_ago
                            ]
                    ]

                Story record ->
                    [ Html.text "by "
                    , Html.a [ Attr.href "TODO user page link" ]
                        [ record.user |> Html.text
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
                    , if record.type_ /= "link" then
                        Html.span
                            [ Attr.class "label"
                            ]
                            [ Html.text <| " " ++ record.type_ ]

                      else
                        Html.text ""
                    ]
            )
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


decoder : Decoder Item
decoder =
    Json.Decode.map2 Item
        (Json.Decode.succeed Common
            |> required "title" Json.Decode.string
            |> required "url" Json.Decode.string
            |> optional "domain" Json.Decode.string ""
            |> required "time_ago" Json.Decode.string
            |> required "comments_count" Json.Decode.int
            |> required "id" Json.Decode.int
        )
        (Json.Decode.field "type" Json.Decode.string
            |> Json.Decode.andThen entryDecoder
        )


entryDecoder type_ =
    if type_ == "job" then
        Json.Decode.succeed Job

    else
        Json.Decode.succeed StoryRecord
            |> required "points" Json.Decode.int
            |> required "user" Json.Decode.string
            |> hardcoded type_
            |> Json.Decode.map Story
