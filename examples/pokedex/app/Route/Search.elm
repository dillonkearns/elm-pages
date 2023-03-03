module Route.Search exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Combined, Field)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Path exposing (Path)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
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
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init static sharedModel =
    ( {}, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update static sharedModel msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias SearchResults =
    { query : String
    , results : List String
    }


type alias Data =
    { results : Maybe SearchResults
    }


type alias ActionData =
    {}


list : List String
list =
    [ "Inspiration Point"
    , "Jesusita"
    ]


data : RouteParams -> Request.Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.formData (form |> Form.initCombined identity)
            |> Request.map
                (\( formResponse, formResult ) ->
                    BackendTask.succeed
                        (Response.render
                            { results =
                                formResult
                                    |> Result.map
                                        (\query ->
                                            Just
                                                { query = query
                                                , results = list |> List.filter (\item -> item |> String.contains query)
                                                }
                                        )
                                    |> Result.withDefault Nothing
                            }
                        )
                )
        , Request.succeed (BackendTask.succeed (Response.render { results = Nothing }))
        ]


form : Form.HtmlForm String String () Msg
form =
    Form.init
        (\query ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap query
            , view =
                \info ->
                    [ query |> fieldView info "Query"
                    , Html.button [] [ Html.text "Search" ]
                    ]
            }
        )
        |> Form.field "q" (Field.text |> Field.required "Required")


fieldView :
    Form.Context String data
    -> String
    -> Field String parsed Form.FieldView.Input
    -> Html msg
fieldView formState label field =
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Form.FieldView.input []
            ]
        , errorsForField formState field
        ]


errorsForField : Form.Context String data -> Field String parsed kind -> Html msg
errorsForField formState field =
    (if True then
        formState.errors
            |> Form.errorsForField field
            |> List.map (\error -> Html.li [] [ Html.text error ])

     else
        []
    )
        |> Html.ul [ Attr.style "color" "red" ]


action : RouteParams -> Request.Parser (BackendTask FatalError (Response ActionData ErrorPage))
action routeParams =
    Request.skip "No action."


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view static sharedModel model =
    { title = "Search"
    , body =
        [ Html.h2 [] [ Html.text "Search" ]
        , form
            |> Form.toDynamicTransition "test1"
            |> Form.withGetMethod
            |> Form.renderHtml []
                -- TODO pass in server data
                (\_ -> Nothing)
                static
                ()
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
            |> List.map (\result -> Html.li [] [ Html.text result ])
            |> Html.ul []
        ]
