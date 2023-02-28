module Route.Profile.Edit exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.User as User exposing (User)
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Validation as Validation
import Form.Value
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Pages.FormState
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
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
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}
    , Effect.none
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


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    { user : User
    }


type alias ActionData =
    Result { fields : List ( String, String ), errors : Dict String (List String) } Action


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> MySession.expectSessionDataOrRedirect (Session.get "userId")
            (\userId () session ->
                User.selection userId
                    |> Request.Hasura.backendTask
                    |> BackendTask.map
                        (\user ->
                            user
                                |> Data
                                |> Response.render
                                |> Tuple.pair session
                        )
            )


type alias Action =
    { username : String
    , name : String
    }


formParser : Form.DoneForm String (BackendTask (Validation.Combined String Action)) Data (List (Html (PagesMsg msg)))
formParser =
    Form.init
        (\username name ->
            { combine =
                Validation.succeed
                    (\u n ->
                        toValidUsername u username
                            |> BackendTask.map
                                (\vu ->
                                    Validation.succeed Action
                                        |> Validation.andMap vu
                                        |> Validation.andMap (Validation.succeed n)
                                )
                    )
                    |> Validation.andMap username
                    |> Validation.andMap name
            , view =
                \info ->
                    let
                        errors field =
                            info.errors
                                |> Form.errorsForField field

                        errorsView field =
                            (-- TODO
                             --if field.status == Pages.FormState.Blurred then
                             if True then
                                info.errors
                                    |> Form.errorsForField field
                                    |> List.map (\error -> Html.li [] [ Html.text error ])

                             else
                                []
                            )
                                |> Html.ul [ Attr.style "color" "red" ]
                    in
                    [ Html.div
                        []
                        [ Html.label [] [ Html.text "Username ", username |> FieldView.input [] ]
                        , errorsView username
                        ]
                    , Html.div []
                        [ Html.label [] [ Html.text "Name ", name |> FieldView.input [] ]
                        , errorsView name
                        ]
                    , Html.button []
                        [ Html.text <|
                            if info.isTransitioning then
                                "Updating..."

                            else
                                "Update"
                        ]
                    ]
            }
        )
        |> Form.field "username"
            (Field.text
                |> Field.required "Username is required"
                |> Field.withClientValidation validateUsername
                |> Field.withInitialValue (\{ user } -> Form.Value.string user.username)
            )
        |> Form.field "name"
            (Field.text
                |> Field.required "Name is required"
                |> Field.withInitialValue (\{ user } -> Form.Value.string user.name)
            )


toValidUsername : String -> Validation.Field String parsed1 field -> BackendTask (Validation.Combined String String)
toValidUsername username usernameField =
    BackendTask.succeed
        (if username == "dillon123" then
            Validation.fail "This username is taken" usernameField

         else
            Validation.succeed username
        )


validateUsername : String -> ( Maybe String, List String )
validateUsername rawUsername =
    if rawUsername |> String.contains "@" then
        ( Just rawUsername, [ "Cannot contain @" ] )

    else
        ( Just rawUsername, [] )


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    Request.formDataWithServerValidation (formParser |> Form.initCombined identity)
        |> MySession.expectSessionDataOrRedirect (Session.get "userId" >> Maybe.map Uuid)
            (\userId parsedActionData session ->
                parsedActionData
                    |> BackendTask.andThen
                        (\parsedAction ->
                            case parsedAction |> Debug.log "parsedAction" of
                                Ok ( response, { name } ) ->
                                    User.updateUser { userId = userId, name = name |> Debug.log "Updating name mutation" }
                                        |> Request.Hasura.mutationBackendTask
                                        |> BackendTask.map
                                            (\_ ->
                                                Route.redirectTo Route.Profile
                                            )
                                        |> BackendTask.map (Tuple.pair session)

                                Err (Form.Response errors) ->
                                    -- TODO need to render errors here?
                                    BackendTask.succeed
                                        (Response.render (Err errors))
                                        |> BackendTask.map (Tuple.pair session)
                        )
            )


head :
    StaticPayload Data ActionData RouteParams
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
        , description = "Update your profile"
        , locale = Nothing
        , title = "Profile"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model app =
    { title = "Ctrl-R Smoothies"
    , body =
        [ Html.p []
            [ Html.text <| "Welcome " ++ app.data.user.name ++ "!" ]
        , case app.action of
            Just (Err error) ->
                error.errors
                    |> Debug.toString
                    |> Html.text

            Nothing ->
                Html.text "No action"

            _ ->
                Html.text "No errors"
        , formParser
            |> Form.toDynamicTransition "edit-form"
            |> Form.renderHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                -- TODO pass in form response from ActionData
                Nothing
                app
                app.data
        ]
    }
