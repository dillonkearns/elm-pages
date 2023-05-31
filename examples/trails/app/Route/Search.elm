module Route.Search exposing (ActionData, Data, Model, Msg, route)

import Api.InputObject
import Api.Object
import Api.Object.Trails
import Api.Query
import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias SearchResults =
    { query : String
    , results : List SearchResult
    }


type alias SearchResult =
    { name : String
    , coverImage : String
    }


type alias Data =
    { results : Maybe SearchResults
    }


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.expectForm
            (\{ field, optionalField } ->
                field "q"
                    |> Request.map
                        (\query ->
                            Request.Hasura.backendTask ""
                                (search query)
                                |> BackendTask.map
                                    (\results ->
                                        Response.render
                                            { results =
                                                Just
                                                    { query = query
                                                    , results = results
                                                    }
                                            }
                                    )
                        )
            )
        , Request.succeed (BackendTask.succeed (Response.render { results = Nothing }))
        ]


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    Request.skip "No action."


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Trail Blazer"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title =
            case static.data.results of
                Nothing ->
                    "Find your next trail"

                Just { results, query } ->
                    query
                        ++ " at TrailBlazer ("
                        ++ String.fromInt (List.length results)
                        ++ " results)"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model static =
    { title = "Search"
    , body =
        [ Html.h2 [] [ Html.text "Search" ]
        , Html.form
            [ Pages.Msg.onSubmit
            ]
            [ Html.label []
                [ Html.text "Query "
                , Html.input [ Attr.name "q" ] []
                ]
            , case static.transition of
                Just _ ->
                    Html.button
                        [ Attr.disabled True
                        ]
                        [ Html.text "Searching..."
                        ]

                Nothing ->
                    Html.button []
                        [ Html.text "Search"
                        ]
            ]
        , static.data.results
            |> Maybe.map resultsView
            |> Maybe.withDefault (Html.div [] [])
        ]
    }


resultsView : SearchResults -> Html msg
resultsView results =
    Html.div []
        [ Html.h2 [] [ Html.text <| "Results matching " ++ results.query ]
        , results.results
            |> List.map
                (\result ->
                    Html.li []
                        [ Html.img
                            [ Attr.src result.coverImage
                            , Attr.style "width" "200px"
                            , Attr.style "border-radius" "10px"
                            ]
                            []
                        , Html.text result.name
                        ]
                )
            |> Html.ul []
        ]


search : String -> SelectionSet (List SearchResult) RootQuery
search query =
    Api.Query.trails
        (\optionals ->
            { optionals
                | where_ =
                    Present
                        (Api.InputObject.buildTrails_bool_exp
                            (\whereOptionals ->
                                { whereOptionals
                                    | name =
                                        Api.InputObject.buildString_comparison_exp
                                            (\stringOptionals ->
                                                { stringOptionals | ilike_ = Present <| "%" ++ query ++ "%" }
                                            )
                                            |> Present
                                }
                            )
                        )
            }
        )
        (SelectionSet.map2 SearchResult
            Api.Object.Trails.name
            Api.Object.Trails.coverImage
        )
