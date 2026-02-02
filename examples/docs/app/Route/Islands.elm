module Route.Islands exposing (ActionData, Data, Model, Msg, route)

{-| Demo page showcasing the Islands architecture with View.freeze.

This server-rendered route demonstrates:

1.  Server-rendered data (request time, user agent)
2.  Frozen content that is server-rendered and adopted by the client
3.  Interactive islands that maintain client-side state

-}

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes as Attr
import Html.Events exposing (onClick)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response
import Shared
import SyntaxHighlight
import Time
import UrlPath
import View exposing (View)


type alias Model =
    { counter : Int
    , selectedTab : Tab
    }


type Tab
    = HowItWorks
    | Benefits
    | CodeExample


type Msg
    = Increment
    | Decrement
    | SelectTab Tab


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias Data =
    { userAgent : String
    , requestTime : Time.Posix
    , method : String
    }


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> BackendTask.fail (FatalError.fromString "No actions")
        }
        |> RouteBuilder.buildWithLocalState
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }


data : RouteParams -> Request -> BackendTask FatalError (Response.Response Data errorPage)
data _ request =
    let
        userAgent =
            Request.header "user-agent" request
                |> Maybe.withDefault "Unknown"

        requestTime =
            Request.requestTime request

        method =
            Request.method request
                |> Request.methodToString
    in
    BackendTask.succeed
        (Response.render
            { userAgent = userAgent
            , requestTime = requestTime
            , method = method
            }
        )


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init _ _ =
    ( { counter = 0
      , selectedTab = HowItWorks
      }
    , Effect.none
    )


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        Increment ->
            ( { model | counter = model.counter + 1 }, Effect.none )

        Decrement ->
            ( { model | counter = model.counter - 1 }, Effect.none )

        SelectTab tab ->
            ( { model | selectedTab = tab }, Effect.none )


subscriptions : RouteParams -> UrlPath.UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions _ _ _ _ =
    Sub.none


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Demo of Islands architecture with frozen views and interactive islands"
        , locale = Nothing
        , title = "Islands Architecture Demo"
        }
        |> Seo.website


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app _ model =
    { title = "Islands Architecture Demo"
    , body =
        [ div [ Attr.class "max-w-4xl mx-auto px-4 py-12" ]
            [ -- Frozen hero section
              View.freeze heroSection

            -- Server-rendered info (frozen, uses ephemeral data)
            , View.freeze (serverInfoSection app.data)

            -- Frozen explanation cards
            , View.freeze explanationCards

            -- Frozen syntax-highlighted code example (tests DCE of SyntaxHighlight)
            , View.freeze syntaxHighlightedCodeExample

            -- Interactive tabbed content (island)
            , tabbedSection model

            -- Interactive counter (island)
            , counterSection model

            -- Frozen footer
            , View.freeze footerSection
            ]
        ]
    }


heroSection : Html Never
heroSection =
    div [ Attr.class "text-center mb-12" ]
        [ h1 [ Attr.class "text-4xl font-bold mb-4" ]
            [ text "Islands Architecture" ]
        , p [ Attr.class "text-xl text-gray-600 max-w-2xl mx-auto" ]
            [ text "Combine server-rendered static content with interactive client-side islands. "
            , text "Get the best of both worlds: fast initial loads and rich interactivity."
            ]
        ]


serverInfoSection : Data -> Html Never
serverInfoSection pageData =
    div
        [ Attr.class "bg-amber-50 border border-amber-200 rounded-lg p-6 mb-8"
        ]
        [ h3 [ Attr.class "font-semibold text-amber-800 mb-2" ]
            [ text "Server-Rendered Data" ]
        , p [ Attr.class "text-amber-700 text-sm mb-2" ]
            [ text "This section shows data from the server request (refresh to see time update):" ]
        , ul [ Attr.class "text-sm text-amber-600 space-y-1" ]
            [ li []
                [ strong [] [ text "Request Time: " ]
                , text (formatTime pageData.requestTime)
                ]
            , li []
                [ strong [] [ text "HTTP Method: " ]
                , text pageData.method
                ]
            , li []
                [ strong [] [ text "User-Agent: " ]
                , text (String.left 60 pageData.userAgent ++ "...")
                ]
            ]
        ]


formatTime : Time.Posix -> String
formatTime time =
    let
        hour =
            Time.toHour Time.utc time |> String.fromInt |> String.padLeft 2 '0'

        minute =
            Time.toMinute Time.utc time |> String.fromInt |> String.padLeft 2 '0'

        second =
            Time.toSecond Time.utc time |> String.fromInt |> String.padLeft 2 '0'

        year =
            Time.toYear Time.utc time |> String.fromInt

        month =
            Time.toMonth Time.utc time |> monthToString

        day =
            Time.toDay Time.utc time |> String.fromInt
    in
    month ++ " " ++ day ++ ", " ++ year ++ " at " ++ hour ++ ":" ++ minute ++ ":" ++ second ++ " UTC"


monthToString : Time.Month -> String
monthToString month =
    case month of
        Time.Jan ->
            "Jan"

        Time.Feb ->
            "Feb"

        Time.Mar ->
            "Mar"

        Time.Apr ->
            "Apr"

        Time.May ->
            "May"

        Time.Jun ->
            "Jun"

        Time.Jul ->
            "Jul"

        Time.Aug ->
            "Aug"

        Time.Sep ->
            "Sep"

        Time.Oct ->
            "Oct"

        Time.Nov ->
            "Nov"

        Time.Dec ->
            "Dec"


explanationCards : Html Never
explanationCards =
    div [ Attr.class "grid md:grid-cols-2 gap-6 mb-8" ]
        [ card "frozen"
            "Frozen Content"
            [ text "Content wrapped in "
            , code [] [ text "View.freeze" ]
            , text " is rendered on the server and adopted by the client without re-rendering. "
            , text "The rendering code is eliminated from the client bundle."
            ]
        , card "island"
            "Interactive Islands"
            [ text "Regular Elm views with "
            , code [] [ text "Model" ]
            , text " and "
            , code [] [ text "Msg" ]
            , text " remain fully interactive. They hydrate on the client and respond to user events."
            ]
        ]


card : String -> String -> List (Html Never) -> Html Never
card cardType title content =
    let
        ( bgColor, borderColor, titleColor ) =
            case cardType of
                "frozen" ->
                    ( "bg-blue-50", "border-blue-200", "text-blue-800" )

                _ ->
                    ( "bg-green-50", "border-green-200", "text-green-800" )
    in
    div
        [ Attr.class ("rounded-lg p-6 border-l-4 " ++ bgColor ++ " " ++ borderColor)
        ]
        [ h3 [ Attr.class ("font-semibold mb-2 " ++ titleColor) ]
            [ text title ]
        , p [ Attr.class "text-gray-700 text-sm" ]
            content
        ]


{-| Syntax-highlighted code example using SyntaxHighlight.
This is inside View.freeze so the SyntaxHighlight code should be DCE'd from the client bundle.
-}
syntaxHighlightedCodeExample : Html Never
syntaxHighlightedCodeExample =
    let
        exampleCode =
            """module Route.Example exposing (route)

import View

route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }

view app =
    { title = "Example"
    , body =
        [ View.freeze
            (h1 [] [ text "Hello!" ])
        ]
    }"""
    in
    div [ Attr.class "bg-gray-800 rounded-lg p-6 mb-8" ]
        [ h3 [ Attr.class "text-white font-semibold mb-3" ]
            [ text "Syntax-Highlighted Example (Frozen)" ]
        , p [ Attr.class "text-gray-300 text-sm mb-4" ]
            [ text "This code block uses the SyntaxHighlight library. Because it's inside View.freeze, the syntax highlighting code is eliminated from the client bundle via DCE." ]
        , div [ Attr.class "overflow-x-auto" ]
            [ SyntaxHighlight.elm exampleCode
                |> Result.map (SyntaxHighlight.toBlockHtml (Just 1))
                |> Result.withDefault
                    (pre [ Attr.class "text-gray-100" ] [ Html.code [] [ text exampleCode ] ])
            ]
        ]


tabbedSection : Model -> Html (PagesMsg Msg)
tabbedSection model =
    div [ Attr.class "bg-white border border-gray-200 rounded-lg mb-8 overflow-hidden" ]
        [ div [ Attr.class "border-b border-gray-200 bg-gray-50" ]
            [ div [ Attr.class "flex" ]
                [ tabButton HowItWorks "How It Works" model.selectedTab
                , tabButton Benefits "Benefits" model.selectedTab
                , tabButton CodeExample "Code Example" model.selectedTab
                ]
            ]
        , div [ Attr.class "p-6" ]
            [ tabContent model.selectedTab
            ]
        ]


tabButton : Tab -> String -> Tab -> Html (PagesMsg Msg)
tabButton tab label selectedTab =
    let
        isSelected =
            tab == selectedTab

        baseClasses =
            "px-4 py-3 text-sm font-medium transition-colors"

        selectedClasses =
            if isSelected then
                " bg-white border-b-2 border-blue-500 text-blue-600"

            else
                " text-gray-500 hover:text-gray-700 hover:bg-gray-100"
    in
    button
        [ onClick (PagesMsg.fromMsg (SelectTab tab))
        , Attr.class (baseClasses ++ selectedClasses)
        ]
        [ text label ]


tabContent : Tab -> Html msg
tabContent tab =
    case tab of
        HowItWorks ->
            div []
                [ p [ Attr.class "mb-4" ]
                    [ text "When you wrap content in "
                    , code [ Attr.class "bg-gray-100 px-1 rounded" ] [ text "View.freeze" ]
                    , text ", elm-pages:"
                    ]
                , ol [ Attr.class "list-decimal list-inside space-y-2 text-gray-700" ]
                    [ li [] [ text "Renders the content on the server" ]
                    , li [] [ text "Extracts it as a static region in the HTML" ]
                    , li [] [ text "On the client, adopts the pre-rendered DOM without re-rendering" ]
                    , li [] [ text "Eliminates the rendering code from the client bundle via DCE" ]
                    ]
                ]

        Benefits ->
            div []
                [ ul [ Attr.class "space-y-3" ]
                    [ benefitItem "Smaller client bundles" "Rendering code for frozen content is dead-code eliminated"
                    , benefitItem "Faster hydration" "No need to re-render static content on the client"
                    , benefitItem "SEO friendly" "All content is in the initial HTML response"
                    , benefitItem "Progressive enhancement" "Static content works without JavaScript"
                    ]
                ]

        CodeExample ->
            div []
                [ pre [ Attr.class "bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto text-sm" ]
                    [ code []
                        [ text """view app model =
    { title = "My Page"
    , body =
        [ -- This content is frozen (server-rendered)
          View.freeze
            (div []
                [ h1 [] [ text "Welcome" ]
                , p [] [ text app.data.description ]
                ]
            )

        -- This is an interactive island
        , button
            [ onClick (PagesMsg.fromMsg Increment) ]
            [ text ("Count: " ++ String.fromInt model.count) ]
        ]
    }"""
                        ]
                    ]
                ]


benefitItem : String -> String -> Html msg
benefitItem title description =
    li [ Attr.class "flex items-start" ]
        [ span [ Attr.class "text-green-500 mr-2" ] [ text "✓" ]
        , div []
            [ strong [ Attr.class "text-gray-800" ] [ text title ]
            , text " — "
            , span [ Attr.class "text-gray-600" ] [ text description ]
            ]
        ]


counterSection : Model -> Html (PagesMsg Msg)
counterSection model =
    div
        [ Attr.class "bg-green-50 border border-green-200 rounded-lg p-6 mb-8"
        ]
        [ h3 [ Attr.class "font-semibold text-green-800 mb-4" ]
            [ text "Interactive Counter (Island)" ]
        , p [ Attr.class "text-green-700 text-sm mb-4" ]
            [ text "This counter maintains client-side state. Try clicking the buttons!" ]
        , div [ Attr.class "flex items-center gap-4" ]
            [ button
                [ onClick (PagesMsg.fromMsg Decrement)
                , Attr.class "w-10 h-10 rounded-full bg-green-600 text-white font-bold hover:bg-green-700 transition-colors"
                ]
                [ text "-" ]
            , span [ Attr.class "text-3xl font-bold text-green-800 min-w-[3rem] text-center" ]
                [ text (String.fromInt model.counter) ]
            , button
                [ onClick (PagesMsg.fromMsg Increment)
                , Attr.class "w-10 h-10 rounded-full bg-green-600 text-white font-bold hover:bg-green-700 transition-colors"
                ]
                [ text "+" ]
            ]
        ]


footerSection : Html Never
footerSection =
    div [ Attr.class "text-center text-gray-500 text-sm pt-8 border-t border-gray-200" ]
        [ p []
            [ text "This entire page demonstrates the Islands architecture. "
            , text "Frozen sections (blue) are server-rendered, while islands (green) are interactive."
            ]
        ]
