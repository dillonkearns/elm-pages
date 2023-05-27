module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.Handler
import Form.Validation as Validation
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages
import Random
import Result.Extra
import Route exposing (Route)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Test.Glob
import Test.HttpRequests
import Test.Runner.Html
import Time
import Xml.Decode


routes :
    BackendTask FatalError (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    let
        html : Html Never -> Response data Never
        html htmlValue =
            htmlToString Nothing htmlValue
                |> Response.body
                |> Response.withHeader "Content-Type" "text/html; charset=UTF-8"
    in
    [ greet
    , ApiRoute.succeed
        (\request ->
            Test.Glob.all
                |> BackendTask.map viewHtmlResults
                |> BackendTask.map html
        )
        |> ApiRoute.literal "tests"
        |> ApiRoute.serverRender
    , ApiRoute.succeed
        (\request ->
            Test.HttpRequests.all
                |> BackendTask.map viewHtmlResults
                |> BackendTask.map html
        )
        |> ApiRoute.literal "http-tests"
        |> ApiRoute.serverRender
    , requestPrinter
    , xmlDecoder
    , multipleContentTypes
    , errorRoute
    ]


errorRoute : ApiRoute ApiRoute.Response
errorRoute =
    ApiRoute.succeed
        (\errorCode request ->
            Response.plainText ("Here is the error code you requested (" ++ errorCode ++ ")")
                |> Response.withStatusCode (String.toInt errorCode |> Maybe.withDefault 500)
                |> BackendTask.succeed
        )
        |> ApiRoute.literal "error-code"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.serverRender


xmlDecoder : ApiRoute ApiRoute.Response
xmlDecoder =
    let
        dataDecoder : Xml.Decode.Decoder String
        dataDecoder =
            Xml.Decode.path [ "path", "to", "string", "value" ] (Xml.Decode.single Xml.Decode.string)
    in
    ApiRoute.succeed
        (\request ->
            --(\_ xmlString  ->
            case ( request |> Request.matchesContentType "application/xml", Request.body request ) of
                ( True, Just xmlString ) ->
                    xmlString
                        |> Xml.Decode.run dataDecoder
                        |> Result.Extra.merge
                        |> Response.plainText
                        |> BackendTask.succeed

                _ ->
                    Response.plainText "Invalid request, expected a body with content-type application/xml."
                        |> Response.withStatusCode 400
                        |> BackendTask.succeed
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "xml"
        |> ApiRoute.serverRender


multipleContentTypes : ApiRoute ApiRoute.Response
multipleContentTypes =
    let
        dataDecoder : Xml.Decode.Decoder String
        dataDecoder =
            Xml.Decode.path [ "path", "to", "string", "value" ] (Xml.Decode.single Xml.Decode.string)
    in
    ApiRoute.succeed
        (\request ->
            case ( request |> Request.body, request |> Request.matchesContentType "application/xml" ) of
                ( Just xmlString, True ) ->
                    xmlString
                        |> Xml.Decode.run dataDecoder
                        |> Result.Extra.merge
                        |> Response.plainText
                        |> BackendTask.succeed

                _ ->
                    case
                        request
                            |> Request.jsonBody
                                (Decode.at [ "path", "to", "string", "value" ] Decode.string)
                    of
                        Just (Ok decodedValue) ->
                            decodedValue
                                |> Response.plainText
                                |> BackendTask.succeed

                        _ ->
                            BackendTask.fail (FatalError.fromString "Invalid request body.")
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "multiple-content-types"
        |> ApiRoute.serverRender


requestPrinter : ApiRoute ApiRoute.Response
requestPrinter =
    ApiRoute.succeed
        (\request ->
            Encode.object
                [ ( "rawBody"
                  , Maybe.map Encode.string (Request.body request)
                        |> Maybe.withDefault Encode.null
                  )
                , ( "method"
                  , Request.method request |> Request.methodToString |> Encode.string
                  )
                , ( "cookies"
                  , Request.cookies request |> Encode.dict identity Encode.string
                  )
                , ( "queryParams"
                  , request |> Request.queryParams |> Encode.dict identity (Encode.list Encode.string)
                  )
                ]
                |> Response.json
                |> BackendTask.succeed
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "request-test"
        |> ApiRoute.serverRender


config : Test.Runner.Html.Config
config =
    Random.initialSeed (Pages.builtAt |> Time.posixToMillis)
        |> Test.Runner.Html.defaultConfig
        |> Test.Runner.Html.hidePassedTests


viewHtmlResults tests =
    Html.div []
        [ Html.h1 [] [ Html.text "My Test Suite" ]
        , Html.div [] [ Test.Runner.Html.viewResults config tests ]
        ]


greet : ApiRoute ApiRoute.Response
greet =
    ApiRoute.succeed
        (\request ->
            let
                jsonBody : Maybe (Result Decode.Error String)
                jsonBody =
                    request |> Request.jsonBody (Decode.field "first" Decode.string)

                asFormData : Maybe ( Form.ServerResponse String, Form.Validated String String )
                asFormData =
                    request
                        |> Request.formData
                            (Form.form
                                (\firstName ->
                                    { combine =
                                        Validation.succeed identity
                                            |> Validation.andMap firstName
                                    , view =
                                        \_ -> ()
                                    }
                                )
                                |> Form.field "first" (Field.text |> Field.required "Required")
                                |> Form.Handler.init identity
                            )

                firstNameResult : Result String String
                firstNameResult =
                    case ( asFormData, jsonBody ) of
                        ( Just ( _, Form.Valid name ), _ ) ->
                            Ok name

                        ( _, Just (Ok name) ) ->
                            Ok name

                        _ ->
                            Err ""
            in
            case firstNameResult of
                Ok firstName ->
                    Response.plainText ("Hello " ++ firstName)
                        |> BackendTask.succeed

                Err _ ->
                    Response.plainText "Invalid request, expected either a JSON body or a 'first=' query param."
                        |> Response.withStatusCode 400
                        |> BackendTask.succeed
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "greet"
        |> ApiRoute.serverRender
