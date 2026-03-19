module Blog exposing (Data, Model, Msg(..), data, init, update, view)

{-| A simple blog app. In a real elm-pages project this would be a Route module
(`app/Route/Blog.elm`). The data/init/update/view functions are identical to
what you'd write in a route module -- the only difference is that a real route
wraps them with `RouteBuilder.single` and `buildNoState`/`buildWithLocalState`.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import FatalError exposing (FatalError)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode


type alias Post =
    { title : String
    , author : String
    , excerpt : String
    }


type alias Data =
    { posts : List Post }


type alias Model =
    { starCount : Maybe Int
    }


type Msg
    = FetchStars
    | GotStars Int


data : BackendTask FatalError Data
data =
    BackendTask.Http.getJson
        "https://api.example.com/posts"
        (Decode.map Data
            (Decode.list
                (Decode.map3 Post
                    (Decode.field "title" Decode.string)
                    (Decode.field "author" Decode.string)
                    (Decode.field "excerpt" Decode.string)
                )
            )
        )
        |> BackendTask.allowFatal


init : Data -> ( Model, List (BackendTask FatalError Msg) )
init _ =
    ( { starCount = Nothing }, [] )


update : Msg -> Model -> ( Model, List (BackendTask FatalError Msg) )
update msg model =
    case msg of
        FetchStars ->
            ( model
            , [ BackendTask.Http.getJson
                    "https://api.github.com/repos/dillonkearns/elm-pages"
                    (Decode.field "stargazers_count" Decode.int)
                    |> BackendTask.allowFatal
                    |> BackendTask.map GotStars
              ]
            )

        GotStars count ->
            ( { model | starCount = Just count }, [] )


view : Data -> Model -> { title : String, body : List (Html Msg) }
view pageData model =
    { title = "Blog"
    , body =
        [ Html.h1 [] [ Html.text "Blog" ]
        , viewStars model.starCount
        , Html.ul []
            (List.map viewPost pageData.posts)
        ]
    }


viewStars : Maybe Int -> Html Msg
viewStars starCount =
    case starCount of
        Nothing ->
            Html.button [ Html.Events.onClick FetchStars ]
                [ Html.text "Show GitHub Stars" ]

        Just count ->
            Html.p [ Attr.class "stars" ]
                [ Html.text ("elm-pages has " ++ String.fromInt count ++ " stars") ]


viewPost : Post -> Html Msg
viewPost post =
    Html.li []
        [ Html.h2 [] [ Html.text post.title ]
        , Html.span [ Attr.class "author" ] [ Html.text ("by " ++ post.author) ]
        , Html.p [] [ Html.text post.excerpt ]
        ]
