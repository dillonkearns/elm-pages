module Route.FrozenViews exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import Color
import Color.Convert
import Color.Manipulate
import Dict
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import FrozenHelper
import FrozenHelperWrapper
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import Html.Styled.Events exposing (onClick)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import Time
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { counter : Int
    }


type Msg
    = Increment
    | Decrement


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias StaticData =
    ()


type alias Data =
    { host : String
    , acceptLanguage : String
    , requestedName : String
    , requestTimeMs : Int
    }


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> BackendTask.succeed (Response.render {})
        }
        |> RouteBuilder.buildWithLocalState
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data _ request =
    let
        requestedName =
            Request.queryParams request
                |> Dict.get "name"
                |> Maybe.andThen List.head
                |> Maybe.withDefault "anonymous"
    in
    BackendTask.succeed
        (Response.render
            { host = Request.header "host" request |> Maybe.withDefault "Unknown"
            , acceptLanguage = Request.header "accept-language" request |> Maybe.withDefault "Not specified"
            , requestedName = requestedName
            , requestTimeMs = Request.requestTime request |> Time.posixToMillis
            }
        )


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init _ _ =
    ( { counter = 0 }, Effect.none )


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        Increment ->
            ( { model | counter = model.counter + 1 }, Effect.none )

        Decrement ->
            ( { model | counter = model.counter - 1 }, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions _ _ _ _ =
    Sub.none


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app _ model =
    { title = "Frozen Views Netlify E2E"
    , body =
        [ Html.div [ Attr.style "max-width" "880px", Attr.style "margin" "0 auto", Attr.style "padding" "24px" ]
            [ Html.h1 [] [ Html.text "Frozen Views (Netlify E2E)" ]
            , Html.p []
                [ Html.a [ Attr.href "/" ] [ Html.text "Back to Index" ]
                ]
            , Html.p []
                [ Html.text "Server-rendered frozen sections and interactive islands."
                ]
            , Html.p []
                [ Html.text "Try "
                , Html.code [] [ Html.text "?name=codex" ]
                , Html.text " and inspect "
                , Html.code [] [ Html.text "content.dat" ]
                , Html.text "."
                ]
            , View.freeze (serverDataSection app.data)
            , FrozenHelperWrapper.summaryCard
                { title = "Transitive helper card A"
                , details = "Route -> wrapper -> freeze helper (first call site)"
                }
            , FrozenHelperWrapper.summaryCard
                { title = "Transitive helper card B"
                , details = "Route -> wrapper -> freeze helper (second call site)"
                }

            -- Cross-module helper with String first arg (tests FID param + String arg seeding)
            , FrozenHelper.badge "e2e-alpha"
            , FrozenHelper.badge "e2e-beta"

            -- Forward-referenced route-local helper with String first arg
            -- (localInfoCard is defined AFTER view in source order)
            , localInfoCard "Local Helper Card" "Route-local helper with String arg, defined after view"
            , localInfoCard "Second Local Card" "Same local helper, second call site"
            -- Color library inside View.freeze (tests DCE of elm-color-extra)
            , View.freeze (colorPaletteSection app.data.requestedName)
            , Html.div
                [ Attr.style "margin-top" "24px"
                , Attr.style "padding" "16px"
                , Attr.style "background" "#ecfeff"
                , Attr.style "border" "1px solid #a5f3fc"
                , Attr.style "border-radius" "8px"
                ]
                [ Html.h3 [ Attr.style "margin-top" "0" ] [ Html.text "Interactive Counter (Island)" ]
                , Html.p [] [ Html.text ("Counter: " ++ String.fromInt model.counter) ]
                , Html.button
                    [ Attr.style "margin-right" "8px"
                    , onClick (PagesMsg.fromMsg Decrement)
                    ]
                    [ Html.text "-" ]
                , Html.button
                    [ onClick (PagesMsg.fromMsg Increment) ]
                    [ Html.text "+" ]
                ]
            ]
        ]
    }


serverDataSection : Data -> Html Never
serverDataSection pageData =
    Html.div
        [ Attr.style "margin-top" "20px"
        , Attr.style "padding" "16px"
        , Attr.style "background" "#fffbeb"
        , Attr.style "border" "1px solid #fcd34d"
        , Attr.style "border-radius" "8px"
        ]
        [ Html.h3 [ Attr.style "margin-top" "0" ] [ Html.text "Live Server Data" ]
        , Html.p [] [ Html.text ("Host: " ++ pageData.host) ]
        , Html.p [] [ Html.text ("Language Preferences: " ++ pageData.acceptLanguage) ]
        , Html.p [] [ Html.text ("Name from query params: " ++ pageData.requestedName) ]
        , Html.p [] [ Html.text ("Request time (ms): " ++ String.fromInt pageData.requestTimeMs) ]
        ]


{-| Forward-referenced route-local helper with String first arg.
Defined AFTER view in source order to exercise the deferred seeding path.
-}
localInfoCard : String -> String -> Html msg
localInfoCard title description =
    View.freeze
        (Html.div
            [ Attr.style "padding" "12px"
            , Attr.style "margin-bottom" "8px"
            , Attr.style "background" "#f0fdfa"
            , Attr.style "border" "1px solid #99f6e4"
            , Attr.style "border-radius" "8px"
            ]
            [ Html.p [ Attr.style "font-weight" "600" ] [ Html.text title ]
            , Html.p [] [ Html.text description ]
            ]
        )


{-| Frozen color palette section that uses elm-color-extra.
The Color.Convert and Color.Manipulate modules should be DCE'd from the client bundle
since this content is only rendered server-side inside View.freeze.
-}
colorPaletteSection : String -> Html Never
colorPaletteSection seedName =
    let
        baseColor =
            Color.hsl (toFloat (String.length seedName) / 10) 0.7 0.5

        lighterColor =
            Color.Manipulate.lighten 0.2 baseColor

        darkerColor =
            Color.Manipulate.darken 0.2 baseColor

        complementColor =
            Color.Manipulate.rotateHue 180 baseColor

        colorSwatch color label =
            Html.div
                [ Attr.style "display" "inline-block"
                , Attr.style "width" "80px"
                , Attr.style "text-align" "center"
                , Attr.style "margin-right" "8px"
                ]
                [ Html.div
                    [ Attr.style "width" "80px"
                    , Attr.style "height" "40px"
                    , Attr.style "border-radius" "4px"
                    , Attr.style "background" (Color.Convert.colorToHex color)
                    ]
                    []
                , Html.p [ Attr.style "font-size" "11px", Attr.style "margin" "4px 0" ]
                    [ Html.text label ]
                , Html.p [ Attr.style "font-size" "10px", Attr.style "color" "#666", Attr.style "margin" "0" ]
                    [ Html.text (Color.Convert.colorToHex color) ]
                ]
    in
    Html.div
        [ Attr.style "margin-top" "20px"
        , Attr.style "padding" "16px"
        , Attr.style "background" "#faf5ff"
        , Attr.style "border" "1px solid #d8b4fe"
        , Attr.style "border-radius" "8px"
        ]
        [ Html.h3 [ Attr.style "margin-top" "0" ] [ Html.text "Frozen Color Palette (DCE Test)" ]
        , Html.p [ Attr.style "font-size" "13px", Attr.style "color" "#666" ]
            [ Html.text ("Generated from seed: " ++ seedName ++ " using elm-color-extra (should be DCE'd from client bundle)") ]
        , Html.div [ Attr.style "display" "flex", Attr.style "gap" "4px", Attr.style "margin-top" "8px" ]
            [ colorSwatch baseColor "Base"
            , colorSwatch lighterColor "Lighter"
            , colorSwatch darkerColor "Darker"
            , colorSwatch complementColor "Complement"
            ]
        ]
