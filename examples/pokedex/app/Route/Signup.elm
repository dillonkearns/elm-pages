module Route.Signup exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Http
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp
    | GotResponse (Result Http.Error ActionData)


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


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action _ =
    Request.expectFormPost
        (\{ field } ->
            Request.map2 Tuple.pair
                (field "first")
                (field "email")
                |> Request.map
                    (\( first, email ) ->
                        validate
                            { email = email
                            , first = first
                            }
                            |> DataSource.succeed
                    )
        )


validate : { first : String, email : String } -> Response ActionData ErrorPage
validate { first, email } =
    if first /= "" && email /= "" then
        Route.redirectTo Route.Signup

    else
        ValidationErrors
            { errors = [ "Cannot be blank" ]
            , fields =
                [ ( "first", first )
                , ( "email", email )
                ]
            }
            |> Response.render


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}
    , static.submit
        { headers = []
        , fields =
            -- TODO when you run a Fetcher and get back a Redirect, how should that be handled? Maybe instead of `Result Http.Error ActionData`,
            -- it should be `FetcherResponse ActionData`, with Redirect as one of the possibilities?
            --[ ( "first", "Jane" )
            --, ( "email", "jane@example.com" )
            --]
            [ ( "first", "" )
            , ( "email", "" )
            ]
        }
        |> Effect.SubmitFetcher
        |> Effect.map GotResponse
    )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        GotResponse result ->
            let
                _ =
                    Debug.log "GotResponse" result
            in
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type ActionData
    = Success { email : String, first : String }
    | ValidationErrors
        { errors : List String
        , fields : List ( String, String )
        }


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed (DataSource.succeed (Response.render Data))


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View Msg
view maybeUrl sharedModel model static =
    { title = "Signup"
    , body =
        [ Html.p []
            [ case static.action of
                Just (Success { email, first }) ->
                    Html.text <| "Hello " ++ first ++ "!"

                Just (ValidationErrors { errors }) ->
                    errors
                        |> List.map (\error -> Html.li [] [ Html.text error ])
                        |> Html.ul []

                _ ->
                    Html.text ""
            ]
        , Html.form
            [ Attr.method "POST"
            ]
            [ Html.label [] [ Html.text "First", Html.input [ Attr.name "first" ] [] ]
            , Html.label [] [ Html.text "Email", Html.input [ Attr.name "email" ] [] ]
            , Html.input [ Attr.type_ "submit", Attr.value "Signup" ] []
            ]
        ]
    }
