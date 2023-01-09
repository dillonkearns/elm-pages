module Route.Signup exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Dict
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Exception exposing (Throwable)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Combined, Field)
import Form.Value
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session exposing (Session)
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


action : RouteParams -> Request.Parser (BackendTask Throwable (Response ActionData ErrorPage))
action _ =
    (Request.formData (form |> Form.initCombined identity)
        |> Request.map (Result.mapError (\error -> "Errors"))
        |> Request.andThen Request.fromResult
    )
        |> MySession.withSession
            (\( first, email ) maybeSession ->
                let
                    session : Session
                    session =
                        maybeSession |> Result.withDefault Session.empty
                in
                validate session
                    { email = email
                    , first = first
                    }
                    |> BackendTask.succeed
            )


validate : Session -> { first : String, email : String } -> ( Session, Response ActionData ErrorPage )
validate session { first, email } =
    if first /= "" && email /= "" then
        ( session
            |> Session.withFlash "message" ("Success! You're all signed up " ++ first)
        , Route.redirectTo Route.Signup
        )

    else
        ( session
        , ValidationErrors
            { errors = [ "Cannot be blank?" ]
            , fields =
                [ ( "first", first )
                , ( "email", email )
                ]
            }
            |> Response.render
        )


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}
    , --static.submit
      --   { headers = []
      --   , fields =
      --       -- TODO when you run a Fetcher and get back a Redirect, how should that be handled? Maybe instead of `Result Http.Error ActionData`,
      --       -- it should be `FetcherResponse ActionData`, with Redirect as one of the possibilities?
      --       --[ ( "first", "Jane" )
      --       --, ( "email", "jane@example.com" )
      --       --]
      --       [ ( "first", "" )
      --       , ( "email", "" )
      --       ]
      --   }
      --   |> Effect.SubmitFetcher
      --   |> Effect.map GotResponse
      Effect.none
    )


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


form : Form.HtmlForm String ( String, String ) data msg
form =
    Form.init
        (\first email ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap first
                    |> Validation.andMap email
            , view =
                \info ->
                    [ first |> fieldView info "First"
                    , email |> fieldView info "Email"
                    , Html.button [] [ Html.text "Sign Up" ]
                    ]
            }
        )
        |> Form.field "first" (Field.text |> required |> Field.withInitialValue (\_ -> Form.Value.string "Jane"))
        |> Form.field "email" (Field.text |> required |> Field.withInitialValue (\_ -> Form.Value.string "jane@example.com"))


required field =
    field |> Field.required "Required"


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
    { flashMessage : Maybe (Result String String)
    }


type ActionData
    = Success { email : String, first : String }
    | ValidationErrors
        { errors : List String
        , fields : List ( String, String )
        }


data : RouteParams -> Request.Parser (BackendTask Throwable (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> MySession.withSession
            (\() sessionResult ->
                let
                    session : Session
                    session =
                        sessionResult |> Result.withDefault Session.empty

                    flashMessage : Maybe String
                    flashMessage =
                        session |> Session.get "message"
                in
                ( Session.empty
                , Response.render
                    { flashMessage = flashMessage |> Maybe.map Ok }
                )
                    |> BackendTask.succeed
            )


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
    -> View (Pages.Msg.Msg Msg)
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
        , flashView static.data.flashMessage
        , form
            |> Form.toDynamicTransition "test1"
            |> Form.renderHtml []
                -- TODO pass in server data
                Nothing
                static
                ()
        ]
    }


flashView : Maybe (Result String String) -> Html msg
flashView message =
    Html.p
        [ Attr.style "background-color" "rgb(163 251 163)"
        ]
        [ Html.text <|
            case message of
                Nothing ->
                    ""

                Just (Ok okMessage) ->
                    okMessage

                Just (Err error) ->
                    "Something went wrong: " ++ error
        ]
