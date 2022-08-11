module Route.Login exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
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
import Form.Validation as Validation exposing (Combined, Field)
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
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import SendGrid
import Server.Request as Request
import Server.Response exposing (Response)
import Server.Session as Session
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


emailToMagicLink : EmailAddress -> DataSource String
emailToMagicLink email =
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
                                "http://localhost:1234/login?magic=" ++ encryptedString
                            )
                    )
            )


form : Form.DoneForm String (DataSource (Combined String EmailAddress)) data (List (Html (Pages.Msg.Msg Msg)))
form =
    Form.init
        (\fieldEmail ->
            { combine =
                Validation.succeed
                    (\email ->
                        DataSource.Env.expect "TODOS_SEND_GRID_KEY"
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
    (if True || formState.submitAttempted then
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
            case magicLinkHash of
                Just magicHash ->
                    parseMagicHashIfNotExpired magicHash
                        |> DataSource.map
                            (\emailIfValid ->
                                let
                                    _ =
                                        Debug.log "@decrypted" emailIfValid
                                in
                                case session of
                                    Ok (Just okSession) ->
                                        ( okSession
                                        , okSession
                                            |> Session.get "userId"
                                            |> Data
                                            |> Server.Response.render
                                        )

                                    _ ->
                                        ( Session.empty
                                        , { username = Nothing }
                                            |> Server.Response.render
                                        )
                            )

                Nothing ->
                    ( Session.empty
                    , { username = Nothing }
                        |> Server.Response.render
                    )
                        |> DataSource.succeed
        )


encryptInfo : String -> Time.Posix -> DataSource String
encryptInfo emailAddress requestTime =
    DataSource.Port.get "encrypt"
        (Encode.object
            [ ( "text", Encode.string emailAddress )
            , ( "expiresAt", requestTime |> Time.posixToMillis |> Encode.int )
            ]
            |> Encode.encode 0
            |> Encode.string
        )
        Decode.string


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Request.map2
        (\sendMagicLinkDataSource requestTime ->
            sendMagicLinkDataSource
                |> DataSource.andThen
                    (\usernameResult ->
                        case usernameResult of
                            Err (Form.Response error) ->
                                Server.Response.render
                                    { maybeError = Just error
                                    , maybeFlash = Nothing
                                    }
                                    |> DataSource.succeed

                            Ok ( _, emailAddress ) ->
                                { maybeError = Nothing
                                , maybeFlash = Just "Check your inbox for your login link!"
                                }
                                    |> Server.Response.render
                                    |> DataSource.succeed
                    )
        )
        (Request.formDataWithServerValidation [ form ])
        Request.requestTime


render :
    Form.Response error
    -> Response { fields : List ( String, String ), errors : Dict String (List error) } a
render (Form.Response response) =
    Server.Response.render response


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Login | elm-pages Todo List"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
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
    , maybeFlash : Maybe String
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel app =
    { title = "Login"
    , body =
        [ Html.p []
            [ Html.text
                (case app.data.username of
                    Just username ->
                        "Hello! You are already logged in."

                    Nothing ->
                        "You aren't logged in yet."
                )
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
    }


sendFake =
    True


sendEmailDataSource : EmailAddress -> String -> DataSource (Result SendGrid.Error ())
sendEmailDataSource recipient apiKey =
    if sendFake then
        emailToMagicLink recipient
            |> DataSource.andThen
                (\magicLinkString ->
                    let
                        emailBody : String
                        emailBody =
                            "Welcome! Please confirm that this is your email address.\n" ++ magicLinkString
                    in
                    log emailBody
                        |> DataSource.map Ok
                )

    else
        let
            senderEmail : Maybe EmailAddress
            senderEmail =
                EmailAddress.fromString "dillon@incrementalelm.com"
        in
        senderEmail
            |> Maybe.map
                (\justSender ->
                    emailToMagicLink recipient
                        |> DataSource.andThen
                            (\magicLinkString ->
                                SendGrid.textEmail
                                    { subject = String.Nonempty.NonemptyString 'T' "odo app login"
                                    , to = List.Nonempty.fromElement recipient
                                    , content = String.Nonempty.NonemptyString 'W' ("elcome! Please confirm that this is your email address.\n" ++ magicLinkString)
                                    , nameOfSender = "Todo App"
                                    , emailAddressOfSender = justSender
                                    }
                                    |> sendEmail apiKey
                            )
                )
            |> Maybe.withDefault (DataSource.fail "Expected a valid sender email address.")


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
                isExpired =
                    (Time.posixToMillis currentTime |> Debug.log "current") > (Time.posixToMillis expiresAt |> Debug.log "expires")
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
