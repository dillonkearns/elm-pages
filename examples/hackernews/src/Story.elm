module Story exposing (..)

import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Route


type alias Story =
    { title : String
    , points : Int
    , user : String
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
            [ Html.text (String.fromInt story.points) ]
        , Html.span
            [ Attr.class "title"
            ]
            (case story.url of
                Just url ->
                    [ Html.a
                        [ Attr.href url
                        , Attr.target "_blank"
                        , Attr.rel "noreferrer"
                        ]
                        [ Html.text story.title ]

                    {-
                       {story.url && !story.url.startsWith("item?id=") ? (
                             <>
                               <a href={story.url} target="_blank" rel="noreferrer">
                                 {story.title}
                               </a>
                               <span class="host"> ({story.domain})</span>
                             </>
                           ) : (
                             <a href={`/item/${story.id}`}>{story.title}</a>
                           )}
                    -}
                    , Html.span [ Attr.class "host" ] [ Html.text <| " (" ++ story.domain ++ ")" ]
                    ]

                Nothing ->
                    [ Html.a
                        [-- TODO decode into custom type here? --Attr.href ("/item/" ++ story.id)
                        ]
                        []
                    ]
            )
        , Html.br []
            []
        , Html.span
            [ Attr.class "meta"
            ]
            [ Html.text "by "
            , Html.a [ Attr.href "TODO" ]
                [ Html.text story.user
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
        , if story.type_ /= "link" then
            Html.span
                [ Attr.class "label"
                ]
                [ Html.text story.type_ ]

          else
            Html.text ""
        ]


decoder : Decoder Story
decoder =
    Json.Decode.succeed Story
        |> required "title" Json.Decode.string
        |> optional "points" Json.Decode.int 0
        |> optional "user" Json.Decode.string ""
        |> required "url" (Json.Decode.nullable Json.Decode.string)
        |> optional "domain" Json.Decode.string ""
        |> required "time_ago" Json.Decode.string
        |> required "comments_count" Json.Decode.int
        |> required "type" Json.Decode.string
        |> required "id" Json.Decode.int
