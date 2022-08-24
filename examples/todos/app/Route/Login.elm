module Route.Login exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Session
import DataSource exposing (DataSource)
import DataSource.Env
import DataSource.Http
import DataSource.Port
import Dict exposing (Dict)
import EmailAddress exposing (EmailAddress)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Combined, Field, Validation)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import List.Nonempty
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import SendGrid
import Server.Request as Request
import Server.Response exposing (Response)
import Server.Session as Session exposing (Session)
import Shared
import String.Nonempty exposing (NonemptyString)
import Time
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Login =
    { username : String
    , password : String
    }


now : DataSource Time.Posix
now =
    DataSource.Port.get "now"
        Encode.null
        (Decode.int |> Decode.map Time.millisToPosix)


emailToMagicLink : EmailAddress -> String -> DataSource String
emailToMagicLink email baseUrl =
    now
        |> DataSource.andThen
            (\now_ ->
                DataSource.Port.get "encrypt"
                    (Encode.object
                        [ ( "text", Encode.string (EmailAddress.toString email) )
                        , ( "expiresAt", (Time.posixToMillis now_ + (1000 * 60 * 30)) |> Encode.int )
                        ]
                        |> Encode.encode 0
                        |> Encode.string
                    )
                    (Decode.string
                        |> Decode.map
                            (\encryptedString ->
                                baseUrl ++ "/login?magic=" ++ encryptedString
                            )
                    )
            )


type alias EnvVariables =
    { sendGridKey : String
    , siteUrl : String
    }


form : Form.DoneForm String (DataSource (Combined String EmailAddress)) data (List (Html (Pages.Msg.Msg Msg)))
form =
    Form.init
        (\fieldEmail ->
            { combine =
                Validation.succeed
                    (\email ->
                        DataSource.map2 EnvVariables
                            (DataSource.Env.expect "TODOS_SEND_GRID_KEY")
                            (DataSource.Env.get "BASE_URL"
                                |> DataSource.map (Maybe.withDefault "http://localhost:1234")
                            )
                            |> DataSource.andThen (sendEmailDataSource email)
                            |> DataSource.map
                                (\emailSendResult ->
                                    case emailSendResult of
                                        Ok () ->
                                            Validation.succeed email

                                        Err error ->
                                            Validation.fail "Whoops, something went wrong sending an email to that address. Try again?" Validation.global
                                )
                    )
                    |> Validation.andMap
                        (fieldEmail
                            |> Validation.map (EmailAddress.fromString >> Result.fromMaybe "Invalid email address")
                            |> Validation.fromResult
                        )
            , view =
                \info ->
                    [ fieldEmail |> fieldView info "Email"
                    , globalErrors info
                    , Html.button []
                        [ if info.isTransitioning then
                            Html.text "Logging in..."

                          else
                            Html.text "Login"
                        ]
                    ]
            }
        )
        |> Form.field "email" (Field.text |> Field.email |> Field.required "Required")
        |> Form.hiddenKind ( "kind", "login" ) "Expected kind"


logoutForm : Form.DoneForm String () data (List (Html (Pages.Msg.Msg Msg)))
logoutForm =
    Form.init
        { combine =
            Validation.succeed ()
        , view =
            \info ->
                [ Html.button []
                    [ if info.isTransitioning then
                        Html.text "Logging out..."

                      else
                        Html.text "Log out"
                    ]
                ]
        }
        |> Form.hiddenKind ( "kind", "logout" ) "Expected kind"


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
    (if formState.submitAttempted then
        formState.errors
            |> Form.errorsForField field
            |> List.map (\error -> Html.li [] [ Html.text error ])

     else
        []
    )
        |> Html.ul [ Attr.style "color" "red" ]


globalErrors : Form.Context String data -> Html msg
globalErrors formState =
    formState.errors
        |> Form.errorsForField Validation.global
        |> List.map (\error -> Html.li [] [ Html.text error ])
        |> Html.ul [ Attr.style "color" "red" ]


type alias Request =
    { cookies : Dict String String
    , maybeFormData : Maybe (Dict String ( String, List String ))
    }


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    MySession.withSession
        (Request.queryParam "magic")
        (\magicLinkHash session ->
            let
                okSessionThing : Session
                okSessionThing =
                    session
                        |> Result.withDefault Nothing
                        |> Maybe.withDefault Session.empty

                maybeSessionId : Maybe String
                maybeSessionId =
                    okSessionThing
                        |> Session.get "sessionId"
            in
            case magicLinkHash of
                Just magicHash ->
                    parseMagicHashIfNotExpired magicHash
                        |> DataSource.andThen
                            (\emailIfValid ->
                                case maybeSessionId of
                                    Just sessionId ->
                                        Data.Session.get sessionId
                                            |> Request.Hasura.dataSource
                                            |> DataSource.map
                                                (\maybeUserSession ->
                                                    ( okSessionThing
                                                    , maybeUserSession
                                                        |> Maybe.map .emailAddress
                                                        |> Data
                                                        |> Server.Response.render
                                                    )
                                                )

                                    Nothing ->
                                        case emailIfValid of
                                            Just confirmedEmail ->
                                                Data.Session.findOrCreateUser confirmedEmail
                                                    |> Request.Hasura.mutationDataSource
                                                    |> DataSource.andThen
                                                        (\userId ->
                                                            now
                                                                |> DataSource.andThen
                                                                    (\now_ ->
                                                                        let
                                                                            expirationTime : Time.Posix
                                                                            expirationTime =
                                                                                Time.millisToPosix (Time.posixToMillis now_ + (1000 * 60 * 30))
                                                                        in
                                                                        Data.Session.create expirationTime userId
                                                                            |> Request.Hasura.mutationDataSource
                                                                    )
                                                        )
                                                    |> DataSource.map
                                                        (\(Uuid sessionId) ->
                                                            ( okSessionThing
                                                                |> Session.insert "sessionId" sessionId
                                                            , Route.Visibility__ { visibility = Nothing }
                                                                |> Route.redirectTo
                                                            )
                                                        )

                                            Nothing ->
                                                DataSource.succeed
                                                    ( okSessionThing
                                                      -- TODO give flash message saying it was an invalid magic link
                                                    , Nothing
                                                        |> Data
                                                        |> Server.Response.render
                                                    )
                            )

                Nothing ->
                    maybeSessionId
                        |> Maybe.map (Data.Session.get >> Request.Hasura.dataSource)
                        |> Maybe.withDefault (DataSource.succeed Nothing)
                        |> DataSource.map
                            (\maybeUserSession ->
                                ( okSessionThing
                                , maybeUserSession
                                    |> Maybe.map .emailAddress
                                    |> Data
                                    |> Server.Response.render
                                )
                            )
        )


allForms : Form.ServerForms String (DataSource (Combined String Action))
allForms =
    logoutForm
        |> Form.toServerForm
        |> Form.initCombinedServer (\_ -> Logout)
        |> Form.combineServer LI form


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    MySession.withSession
        (Request.map2 Tuple.pair
            (Request.oneOf
                [ Request.formDataWithServerValidation allForms
                ]
            )
            Request.requestTime
        )
        (\( resolveFormDataSource, requestTime ) session ->
            resolveFormDataSource
                |> DataSource.andThen
                    (\usernameResult ->
                        let
                            okSession =
                                session
                                    |> Result.withDefault Nothing
                                    |> Maybe.withDefault Session.empty
                        in
                        case usernameResult of
                            Err (Form.Response error) ->
                                ( okSession
                                , Server.Response.render
                                    { maybeError = Just error
                                    , sentLink = False
                                    }
                                )
                                    |> DataSource.succeed

                            Ok ( _, Logout ) ->
                                ( Session.empty
                                , Route.redirectTo Route.Login
                                )
                                    |> DataSource.succeed

                            Ok ( _, LI emailAddress ) ->
                                ( okSession
                                , { maybeError = Nothing
                                  , sentLink = True
                                  }
                                    |> Server.Response.render
                                )
                                    |> DataSource.succeed
                    )
        )


type Action
    = LI EmailAddress
    | Logout


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Login | elm-pages Todo List"
        , image =
            { url = Pages.Url.external "https://images.unsplash.com/photo-1499750310107-5fef28a66643?ixlib=rb-1.2.1&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=600&q=80"
            , alt = "Desk with a Todo List"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Login to manage your todo list in full-stack Elm!"
        , locale = Nothing
        , title = "Login | elm-pages Todo List"
        }
        |> Seo.website


type alias Data =
    { username : Maybe String
    }


type alias ActionData =
    { maybeError :
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List String)
            }
    , sentLink : Bool
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel app =
    { title = "Login"
    , body =
        [ if app.action |> Maybe.map .sentLink |> Maybe.withDefault False then
            Html.text "Check your inbox for your login link!"

          else
            Html.div []
                [ Html.p []
                    [ case app.data.username of
                        Just username ->
                            Html.div []
                                [ Html.text <| "Hello! You are already logged in as " ++ username
                                , logoutForm
                                    |> Form.toDynamicTransition "logout"
                                    |> Form.renderHtml []
                                        Nothing
                                        app
                                        ()
                                ]

                        Nothing ->
                            Html.text "You aren't logged in yet."
                    ]
                , form
                    |> Form.toDynamicTransition "login"
                    |> Form.renderHtml []
                        (app.action
                            |> Maybe.andThen .maybeError
                        )
                        app
                        ()
                ]
        ]
    }


sendFake : Bool
sendFake =
    False


sendEmailDataSource : EmailAddress -> EnvVariables -> DataSource (Result SendGrid.Error ())
sendEmailDataSource recipient env =
    emailToMagicLink recipient env.siteUrl
        |> DataSource.andThen
            (\magicLinkString ->
                let
                    message : NonemptyString
                    message =
                        String.Nonempty.NonemptyString 'W' ("elcome! Please confirm that this is your email address.\n" ++ magicLinkString)
                in
                if sendFake then
                    message
                        |> String.Nonempty.toString
                        |> log
                        |> DataSource.map Ok

                else
                    let
                        senderEmail : Maybe EmailAddress
                        senderEmail =
                            EmailAddress.fromString "dillon@incrementalelm.com"
                    in
                    senderEmail
                        |> Maybe.map
                            (\justSender ->
                                SendGrid.textEmail
                                    { subject = String.Nonempty.NonemptyString 'T' "odo app login"
                                    , to = List.Nonempty.fromElement recipient
                                    , content = message
                                    , nameOfSender = "Todo App"
                                    , emailAddressOfSender = justSender
                                    }
                                    |> sendEmail env.sendGridKey
                            )
                        |> Maybe.withDefault (DataSource.fail "Expected a valid sender email address.")
            )


sendEmail :
    String
    -> SendGrid.Email
    -> DataSource (Result SendGrid.Error ())
sendEmail apiKey_ email_ =
    DataSource.Http.uncachedRequest
        { method = "POST"
        , headers = [ ( "Authorization", "Bearer " ++ apiKey_ ) ]
        , url = SendGrid.sendGridApiUrl
        , body = SendGrid.encodeSendEmail email_ |> DataSource.Http.jsonBody
        }
        DataSource.Http.expectStringResponse
        |> DataSource.map
            (\response ->
                case response of
                    DataSource.Http.BadUrl_ url ->
                        SendGrid.BadUrl url |> Err

                    DataSource.Http.Timeout_ ->
                        Err SendGrid.Timeout

                    DataSource.Http.NetworkError_ ->
                        Err SendGrid.NetworkError

                    DataSource.Http.BadStatus_ metadata body ->
                        SendGrid.decodeBadStatus metadata body |> Err

                    DataSource.Http.GoodStatus_ _ _ ->
                        Ok ()
            )


parseMagicHash : String -> DataSource ( String, Time.Posix )
parseMagicHash magicHash =
    DataSource.Port.get "decrypt"
        (Encode.string magicHash)
        (Decode.string
            |> Decode.map
                (Decode.decodeString
                    (Decode.map2 Tuple.pair
                        (Decode.field "text" Decode.string)
                        (Decode.field "expiresAt" (Decode.int |> Decode.map Time.millisToPosix))
                    )
                    >> Result.mapError Decode.errorToString
                )
        )
        |> DataSource.andThen DataSource.fromResult


parseMagicHashIfNotExpired : String -> DataSource (Maybe String)
parseMagicHashIfNotExpired magicHash =
    DataSource.map2
        (\( email, expiresAt ) currentTime ->
            let
                isExpired : Bool
                isExpired =
                    Time.posixToMillis currentTime > Time.posixToMillis expiresAt
            in
            if isExpired then
                Nothing

            else
                Just email
        )
        (parseMagicHash magicHash)
        now


log : String -> DataSource ()
log message =
    DataSource.Port.get "log"
        (Encode.string message)
        (Decode.succeed ())
