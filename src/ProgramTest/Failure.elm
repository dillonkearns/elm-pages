module ProgramTest.Failure exposing (Failure(..), toString)

import Html exposing (Html)
import ProgramTest.ComplexQuery as ComplexQuery exposing (Failure(..), FailureContext1(..))
import ProgramTest.TestHtmlHacks as TestHtmlHacks
import Set
import String.Extra
import Test.Html.Query as Query
import Test.Runner.Failure
import Url exposing (Url)
import Vendored.Failure
import Vendored.FormatMonochrome


type Failure
    = ChangedPage String Url
      -- Errors
    | ExpectFailed String String Test.Runner.Failure.Reason
    | SimulateFailed String String
    | SimulateFailedToFindTarget String String
    | SimulateLastEffectFailed String
    | InvalidLocationUrl String String
    | InvalidFlags String String
    | ProgramDoesNotSupportNavigation String
    | NoBaseUrl String String
    | NoMatchingHttpRequest Int Int String { method : String, url : String } (List ( String, String ))
    | MultipleMatchingHttpRequest Int Int String { method : String, url : String } (List ( String, String ))
    | EffectSimulationNotConfigured String
    | ViewAssertionFailed String (Html ()) ComplexQuery.Highlight ( ComplexQuery.FailureContext, ComplexQuery.Failure )
    | CustomFailure String String


toString : Failure -> String
toString failure =
    case failure of
        ChangedPage cause finalLocation ->
            cause ++ " caused the program to end by navigating to " ++ String.Extra.escape (Url.toString finalLocation) ++ ".  NOTE: If this is what you intended, use ProgramTest.expectPageChange to end your test."

        ExpectFailed expectationName description reason ->
            expectationName
                ++ ":\n"
                ++ Vendored.Failure.format
                    Vendored.FormatMonochrome.formatEquality
                    description
                    reason

        SimulateFailed functionName message ->
            functionName ++ ":\n" ++ message

        SimulateFailedToFindTarget functionName message ->
            functionName ++ ":\n" ++ message

        SimulateLastEffectFailed message ->
            "simulateLastEffect failed: " ++ message

        InvalidLocationUrl functionName invalidUrl ->
            functionName ++ ": " ++ "Not a valid absolute URL:\n" ++ String.Extra.escape invalidUrl

        InvalidFlags functionName message ->
            functionName ++ ":\n" ++ message

        ProgramDoesNotSupportNavigation functionName ->
            functionName ++ ": Program does not support navigation.  Use ProgramTest.createApplication to create a ProgramTest that supports navigation."

        NoBaseUrl functionName relativeUrl ->
            functionName ++ ": The ProgramTest does not have a base URL and cannot resolve the relative URL " ++ String.Extra.escape relativeUrl ++ ".  Use ProgramTest.withBaseUrl before calling ProgramTest.start to create a ProgramTest that can resolve relative URLs."

        NoMatchingHttpRequest expected actual functionName request pendingRequests ->
            String.concat
                [ functionName
                , ": "
                , "Expected "
                , case expected of
                    1 ->
                        "HTTP request"

                    _ ->
                        "at least " ++ String.fromInt expected ++ " HTTP requests"
                , " ("
                , request.method
                , " "
                , request.url
                , ") to have been made and still be pending, "
                , case actual of
                    0 ->
                        "but no such requests were made."

                    _ ->
                        "but only " ++ String.fromInt actual ++ " such requests were made."
                , "\n"
                , case pendingRequests of
                    [] ->
                        "    No requests were made."

                    _ ->
                        String.concat
                            [ "    The following requests were made:\n"
                            , String.join "\n" <|
                                List.map (\( method, url ) -> "      - " ++ method ++ " " ++ url) pendingRequests
                            ]
                ]

        MultipleMatchingHttpRequest expected actual functionName request pendingRequests ->
            String.concat
                [ functionName
                , ": "
                , "Expected "
                , case expected of
                    1 ->
                        "a single HTTP request"

                    _ ->
                        String.fromInt expected ++ " HTTP requests"
                , " ("
                , request.method
                , " "
                , request.url
                , ") to have been made, but "
                , String.fromInt actual
                , " such requests were made.\n"
                , case pendingRequests of
                    [] ->
                        "    No requests were made."

                    _ ->
                        String.concat
                            [ "    The following requests were made:\n"
                            , String.join "\n" <|
                                List.map (\( method, url ) -> "      - " ++ method ++ " " ++ url) pendingRequests
                            ]
                , if expected == 1 && actual > 1 then
                    let
                        useInstead =
                            if String.startsWith "simulate" functionName then
                                "simulateHttpResponseAdvanced"

                            else if String.startsWith "expect" functionName then
                                "expectHttpRequests"

                            else
                                "ensureHttpRequests"
                    in
                    "\n\nNOTE: If you want to allow multiple requests to the same endpoint, use ProgramTest." ++ useInstead ++ "."

                  else
                    ""
                ]

        EffectSimulationNotConfigured functionName ->
            "TEST SETUP ERROR: In order to use " ++ functionName ++ ", you MUST use ProgramTest.withSimulatedEffects before calling ProgramTest.start"

        ViewAssertionFailed functionName html highlight reason ->
            let
                highlighter =
                    if Set.isEmpty highlight then
                        \_ _ _ -> True

                    else
                        \tag attrs children ->
                            Set.member tag highlight
            in
            String.join "\n"
                [ TestHtmlHacks.renderHtml showColors.dim highlighter (Query.fromHtml html)
                , ""
                , "▼ " ++ functionName
                , ""
                , renderQueryFailureWithContext renderQueryFailure 0 True reason
                ]

        CustomFailure assertionName message ->
            assertionName ++ ": " ++ message


renderQueryFailureWithContext : (Int -> Bool -> a -> String) -> Int -> Bool -> ( ComplexQuery.FailureContext, a ) -> String
renderQueryFailureWithContext renderInner indent color failure =
    let
        indentS =
            String.repeat indent " "
    in
    case failure of
        ( [], inner ) ->
            renderInner indent color inner

        ( (Description description) :: baseFailure, inner ) ->
            String.join "\n" <|
                List.filter ((/=) "")
                    [ indentS ++ renderDescriptionResult (colorsFor color) description ++ ":"
                    , renderQueryFailureWithContext renderInner (indent + 2) color ( baseFailure, inner )
                    ]

        ( (CheckSucceeded description checkContext) :: baseFailure, inner ) ->
            String.join "\n" <|
                List.filter ((/=) "")
                    [ indentS ++ renderDescriptionResult (colorsFor color) (Ok description) ++ ":"
                    , renderQueryFailureWithContext_ (\_ _ () -> "") (indent + 2) color ( checkContext, () )
                    , renderQueryFailureWithContext renderInner indent color ( baseFailure, inner )
                    ]

        ( (FindSucceeded (Just description) successfulChecks) :: baseFailure, inner ) ->
            String.join "\n" <|
                List.filter ((/=) "")
                    [ indentS ++ renderDescriptionResult (colorsFor color) (Ok description) ++ ":"
                    , renderSelectorResults (indent + 2) (colorsFor color) (List.map Ok (successfulChecks ()))
                    , renderQueryFailureWithContext renderInner indent color ( baseFailure, inner )
                    ]

        ( (FindSucceeded Nothing successfulChecks) :: baseFailure, inner ) ->
            String.join "\n" <|
                List.filter ((/=) "")
                    [ renderSelectorResults indent (colorsFor color) (List.map Ok (successfulChecks ()))
                    , renderQueryFailureWithContext renderInner indent color ( baseFailure, inner )
                    ]


renderQueryFailureWithContext_ : (Int -> Bool -> a -> String) -> Int -> Bool -> ( ComplexQuery.FailureContext, a ) -> String
renderQueryFailureWithContext_ =
    renderQueryFailureWithContext


renderQueryFailure : Int -> Bool -> ComplexQuery.Failure -> String
renderQueryFailure indent color failure =
    let
        indentS =
            String.repeat indent " "
    in
    case failure of
        QueryFailed failureReason ->
            renderSelectorResults indent (colorsFor color) failureReason

        ComplexQuery.SimulateFailed string ->
            let
                colors =
                    colorsFor color
            in
            indentS ++ renderSelectorResult colors (Err string)

        NoMatches description options ->
            let
                sortedByPriority =
                    options
                        |> List.sortBy (\( _, prio, _ ) -> -prio)

                maxPriority =
                    List.head sortedByPriority
                        |> Maybe.map (\( _, prio, _ ) -> prio)
                        |> Maybe.withDefault 0
            in
            String.join "\n" <|
                List.concat
                    [ [ indentS ++ description ++ ":" ]
                    , sortedByPriority
                        |> List.filter (\( _, prio, _ ) -> prio > maxPriority - 2)
                        |> List.map (\( desc, prio, reason ) -> indentS ++ "- " ++ desc ++ "\n" ++ renderQueryFailureWithContext renderQueryFailure (indent + 4) (color && prio >= maxPriority - 1) reason)
                    ]

        TooManyMatches description matches ->
            String.join "\n" <|
                List.concat
                    [ [ indentS ++ description ++ ", but there were multiple successful matches:" ]
                    , matches
                        |> List.sortBy (\( _, prio, _ ) -> -prio)
                        |> List.map (\( desc, _, todo ) -> indentS ++ "- " ++ desc)
                    , [ ""
                      , "If that's what you intended, use `ProgramTest.within` to focus in on a portion of"
                      , "the view that contains only one of the matches."
                      ]
                    ]


renderSelectorResults : Int -> Colors -> List (Result String String) -> String
renderSelectorResults indent colors results =
    let
        indentS =
            String.repeat indent " "
    in
    List.map ((++) indentS << renderSelectorResult colors) (upToFirstErr results)
        |> String.join "\n"


renderSelectorResult : Colors -> Result String String -> String
renderSelectorResult colors result =
    case result of
        Ok selector ->
            String.concat
                [ colors.green "✓"
                , " "
                , colors.bold selector
                ]

        Err selector ->
            colors.red <|
                String.concat
                    [ "✗"
                    , " "
                    , selector
                    ]


renderDescriptionResult : Colors -> Result String String -> String
renderDescriptionResult colors result =
    case result of
        Ok selector ->
            String.concat
                [ colors.green "✓"
                , " "
                , selector
                ]

        Err selector ->
            String.concat
                [ colors.red "✗"
                , " "
                , selector
                ]


upToFirstErr : List (Result x a) -> List (Result x a)
upToFirstErr results =
    let
        step acc results_ =
            case results_ of
                [] ->
                    acc

                (Err x) :: _ ->
                    Err x :: acc

                (Ok a) :: rest ->
                    step (Ok a :: acc) rest
    in
    step [] results
        |> List.reverse


type alias Colors =
    { bold : String -> String
    , red : String -> String
    , green : String -> String
    , dim : String -> String
    }


colorsFor : Bool -> Colors
colorsFor show =
    if show then
        showColors

    else
        noColors


showColors : Colors
showColors =
    { bold = \s -> String.concat [ "\u{001B}[1m", s, "\u{001B}[0m" ]
    , red = \s -> String.concat [ "\u{001B}[31m", s, "\u{001B}[0m" ]
    , green = \s -> String.concat [ "\u{001B}[32m", s, "\u{001B}[0m" ]
    , dim = \s -> String.concat [ "\u{001B}[2m", s, "\u{001B}[0m" ]
    }


noColors : Colors
noColors =
    { bold = identity
    , red = identity
    , green = identity
    , dim = identity
    }
