module Route.Login exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.Env
import BackendTask.Http
import BackendTask.Time
import EmailAddress exposing (EmailAddress)
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
import Json.Decode as Decode
import Json.Encode as Encode
import List.Nonempty
import MySession
import Pages.Script as Script
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
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


emailToMagicLink : EmailAddress -> String -> BackendTask FatalError String
emailToMagicLink email baseUrl =
    BackendTask.Time.now
        |> BackendTask.andThen
            (\now_ ->
                BackendTask.Custom.run "encrypt"
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
        |> BackendTask.allowFatal


type alias EnvVariables =
    { sendGridKey : String
    , siteUrl : String
    }


form : Form.DoneForm String (BackendTask FatalError (Combined String EmailAddress)) data (List (Html (PagesMsg Msg))) Msg
form =
    Form.init
        (\fieldEmail ->
            { combine =
                Validation.succeed
                    (\email ->
                        BackendTask.map2 EnvVariables
                            (BackendTask.Env.expect "TODOS_SEND_GRID_KEY" |> BackendTask.allowFatal)
                            (BackendTask.Env.get "BASE_URL"
                                |> BackendTask.map (Maybe.withDefault "http://localhost:1234")
                            )
                            |> BackendTask.andThen (sendEmailBackendTask email)
                            |> BackendTask.map
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


logoutForm : Form.DoneForm String () data (List (Html (PagesMsg Msg))) Msg
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


data : RouteParams -> Request.Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.queryParam "magic"
        |> MySession.withSession
            (\magicLinkHash session ->
                let
                    okSessionThing : Session
                    okSessionThing =
                        session
                            |> Result.withDefault Session.empty

                    maybeSessionId : Maybe String
                    maybeSessionId =
                        okSessionThing
                            |> Session.get "sessionId"
                in
                case magicLinkHash of
                    Just magicHash ->
                        parseMagicHashIfNotExpired magicHash
                            |> BackendTask.andThen
                                (\emailIfValid ->
                                    case maybeSessionId of
                                        Just sessionId ->
                                            BackendTask.Custom.run
                                                "getEmailBySessionId"
                                                (Encode.string sessionId)
                                                (Decode.maybe Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map
                                                    (\maybeUserSession ->
                                                        ( okSessionThing
                                                        , maybeUserSession
                                                            |> Data
                                                            |> Server.Response.render
                                                        )
                                                    )

                                        Nothing ->
                                            case emailIfValid of
                                                Just confirmedEmail ->
                                                    BackendTask.Time.now
                                                        |> BackendTask.andThen
                                                            (\now_ ->
                                                                let
                                                                    expirationTime : Time.Posix
                                                                    expirationTime =
                                                                        Time.millisToPosix (Time.posixToMillis now_ + (1000 * 60 * 30))
                                                                in
                                                                BackendTask.Custom.run "findOrCreateUserAndSession"
                                                                    (Encode.object
                                                                        [ ( "confirmedEmail"
                                                                          , Encode.string confirmedEmail
                                                                          )
                                                                        , ( "expirationTime", expirationTime |> Time.posixToMillis |> Encode.int )
                                                                        ]
                                                                    )
                                                                    Decode.string
                                                                    |> BackendTask.allowFatal
                                                            )
                                                        |> BackendTask.map
                                                            (\sessionId ->
                                                                ( okSessionThing
                                                                    |> Session.insert "sessionId" sessionId
                                                                , Route.Visibility__ { visibility = Nothing }
                                                                    |> Route.redirectTo
                                                                )
                                                            )

                                                Nothing ->
                                                    BackendTask.succeed
                                                        ( okSessionThing
                                                          -- TODO give flash message saying it was an invalid magic link
                                                        , Nothing
                                                            |> Data
                                                            |> Server.Response.render
                                                        )
                                )

                    Nothing ->
                        maybeSessionId
                            |> Maybe.map
                                (\sessionId ->
                                    BackendTask.Custom.run
                                        "getEmailBySessionId"
                                        (Encode.string sessionId)
                                        (Decode.maybe Decode.string)
                                )
                            |> Maybe.withDefault (BackendTask.succeed Nothing)
                            |> BackendTask.allowFatal
                            |> BackendTask.map
                                (\maybeEmail ->
                                    ( okSessionThing
                                    , maybeEmail
                                        |> Data
                                        |> Server.Response.render
                                    )
                                )
            )


allForms : Form.ServerForms String (BackendTask FatalError (Combined String Action))
allForms =
    logoutForm
        |> Form.toServerForm
        |> Form.initCombinedServer (\_ -> Logout)
        |> Form.combineServer LogIn form


action : RouteParams -> Request.Parser (BackendTask FatalError (Response ActionData ErrorPage))
action routeParams =
    Request.map2 Tuple.pair
        (Request.oneOf
            [ Request.formDataWithServerValidation allForms
            ]
        )
        Request.requestTime
        |> MySession.withSession
            (\( resolveFormBackendTask, requestTime ) session ->
                resolveFormBackendTask
                    |> BackendTask.andThen
                        (\usernameResult ->
                            let
                                okSession =
                                    session
                                        |> Result.withDefault Session.empty
                            in
                            case usernameResult of
                                Err error ->
                                    ( okSession
                                    , Server.Response.render
                                        { maybeError = Just error
                                        , sentLink = False
                                        }
                                    )
                                        |> BackendTask.succeed

                                Ok ( _, Logout ) ->
                                    ( Session.empty
                                    , Route.redirectTo Route.Login
                                    )
                                        |> BackendTask.succeed

                                Ok ( _, LogIn emailAddress ) ->
                                    ( okSession
                                    , { maybeError = Nothing
                                      , sentLink = True
                                      }
                                        |> Server.Response.render
                                    )
                                        |> BackendTask.succeed
                        )
            )


type Action
    = LogIn EmailAddress
    | Logout


head :
    App Data ActionData RouteParams
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
    { maybeError : Maybe (Form.Response String)
    , sentLink : Bool
    }


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
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
                                    |> Form.toDynamicTransition
                                    |> Form.renderHtml "logout"
                                        []
                                        (\_ -> Nothing)
                                        app
                                        ()
                                ]

                        Nothing ->
                            Html.text "You aren't logged in yet."
                    ]
                , form
                    |> Form.renderHtml "login" [] .maybeError app ()
                ]
        ]
    }


sendFake : Bool
sendFake =
    False


sendEmailBackendTask : EmailAddress -> EnvVariables -> BackendTask FatalError (Result SendGrid.Error ())
sendEmailBackendTask recipient env =
    emailToMagicLink recipient env.siteUrl
        |> BackendTask.andThen
            (\magicLinkString ->
                let
                    message : NonemptyString
                    message =
                        String.Nonempty.NonemptyString 'W' ("elcome! Please confirm that this is your email address.\n" ++ magicLinkString)
                in
                if sendFake then
                    message
                        |> String.Nonempty.toString
                        |> Script.log
                        |> BackendTask.map Ok

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
                        |> Maybe.withDefault (BackendTask.fail (FatalError.fromString "Expected a valid sender email address."))
            )


sendEmail :
    String
    -> SendGrid.Email
    -> BackendTask noError (Result SendGrid.Error ())
sendEmail apiKey_ email_ =
    BackendTask.Http.request
        { method = "POST"
        , headers = [ ( "Authorization", "Bearer " ++ apiKey_ ) ]
        , url = SendGrid.sendGridApiUrl
        , body = SendGrid.encodeSendEmail email_ |> BackendTask.Http.jsonBody
        , retries = Nothing
        , timeoutInMs = Nothing
        }
        (BackendTask.Http.expectWhatever ())
        |> BackendTask.mapError
            (\response ->
                case response.recoverable of
                    BackendTask.Http.BadUrl url ->
                        SendGrid.BadUrl url

                    BackendTask.Http.Timeout ->
                        SendGrid.Timeout

                    BackendTask.Http.NetworkError ->
                        SendGrid.NetworkError

                    BackendTask.Http.BadStatus metadata body ->
                        SendGrid.decodeBadStatus metadata body

                    BackendTask.Http.BadBody maybeError string ->
                        SendGrid.BadUrl ""
            )
        |> BackendTask.toResult


parseMagicHash : String -> BackendTask FatalError ( String, Time.Posix )
parseMagicHash magicHash =
    BackendTask.Custom.run "decrypt"
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
        |> BackendTask.allowFatal
        |> BackendTask.andThen (BackendTask.fromResult >> BackendTask.mapError FatalError.fromString)


parseMagicHashIfNotExpired : String -> BackendTask FatalError (Maybe String)
parseMagicHashIfNotExpired magicHash =
    BackendTask.map2
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
        BackendTask.Time.now
