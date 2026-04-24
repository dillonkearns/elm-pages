module Test.PagesProgram.Viewer exposing (app, Flags, Model, Msg)

{-| A browser-based visual test runner that lets you step through elm-pages
test snapshots in your browser. Displays a Cypress-style command log sidebar
alongside the rendered page view.

    module TestViewer exposing (main)

    import Test.PagesProgram as PagesProgram
    import Test.PagesProgram.Viewer as Viewer

    main =
        Viewer.app
            [ ( "Blog loads posts"
              , myBlogTest |> PagesProgram.toSnapshots
              )
            , ( "Counter increments"
              , myCounterTest |> PagesProgram.toSnapshots
              )
            ]

Open the compiled HTML in your browser, then use arrow keys to step through.

The Cookies sidebar (`c`) displays signed session cookies with the secret
that was used. Note: the in-memory "checksum" shown next to the secret is a
fast non-cryptographic FNV1a hash, not a real HMAC-SHA256 — it only exists
so the visual runner can distinguish different secrets and detect
test-time tampering of signed-cookie payloads.

@docs app, Flags, Model, Msg

-}

import Browser
import Browser.Dom
import Browser.Events
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)
import Task
import Test.BackendTask.Internal as BackendTaskTest
import Test.PagesProgram.CookieJar as CookieJar exposing (CookieEntry)
import Test.PagesProgram.DebugParser as DebugParser
import Test.PagesProgram.Internal exposing (AssertionSelector(..), FetcherEntry, FetcherStatus(..), NetworkEntry, NetworkSource(..), NetworkStatus(..), Snapshot, StepKind(..), TargetSelector(..))
import Test.PagesProgram.Viewer.Icons as Icons
import Url exposing (Url)


{-| Flags for the viewer app. Currently unused.
-}
type alias Flags =
    ()


type SidebarMode
    = TestList
    | CommandLog


{-| The viewer's model.
-}
type alias Model =
    { tests : List NamedTest
    , currentTestIndex : Int
    , currentStepIndex : Int
    , hoveredStepIndex : Maybe Int
    , showModel : Bool
    , sidebarMode : SidebarMode
    , navKey : Nav.Key
    , basePath : String
    , searchQuery : String
    , viewportWidth : Maybe Int
    , showEffects : Bool
    , showNetwork : Bool
    , showNetworkBackend : Bool
    , showNetworkFrontend : Bool
    , showFetchers : Bool
    , showCookies : Bool
    , previewMode : PreviewMode
    , expandedGroups : Set Int
    , modelTreeExpanded : Set String
    }


type PreviewMode
    = After
    | Before


type alias NamedTest =
    { name : String
    , snapshots : List Snapshot
    }


{-| The viewer's messages.
-}
type Msg
    = NextStep
    | PrevStep
    | GoToStep Int
    | NextTest
    | PrevTest
    | GoToTest Int
    | HoverStep Int
    | UnhoverStep
    | ShowTestList
    | ToggleModel
    | KeyDown String
    | UpdateSearch String
    | SetViewport (Maybe Int)
    | ToggleEffects
    | ToggleNetwork
    | ToggleNetworkBackend
    | ToggleNetworkFrontend
    | ToggleFetchers
    | ToggleCookies
    | SetPreviewMode PreviewMode
    | ToggleGroup Int
    | ToggleModelNode String
    | UrlChanged Url
    | LinkClicked Browser.UrlRequest
    | NoOp


{-| Create a visual test runner application. Pass a list of named tests with
their snapshots.

    main =
        Viewer.app
            [ ( "my test", myTest |> PagesProgram.toSnapshots )
            ]

-}
app : List ( String, List Snapshot ) -> Program Flags Model Msg
app tests =
    let
        namedTests =
            tests
                |> List.map
                    (\( name, snapshots ) ->
                        { name = name, snapshots = snapshots }
                    )
    in
    Browser.application
        { init =
            \_ url key ->
                let
                    basePath =
                        extractBasePath url

                    testNameFromUrl =
                        extractTestName basePath url

                    ( initialTestIndex, initialMode ) =
                        case testNameFromUrl of
                            Just name ->
                                case findTestIndex name namedTests of
                                    Just idx ->
                                        ( idx, CommandLog )

                                    Nothing ->
                                        ( 0
                                        , if List.length namedTests > 1 then
                                            TestList

                                          else
                                            CommandLog
                                        )

                            Nothing ->
                                ( 0
                                , if List.length namedTests > 1 then
                                    TestList

                                  else
                                    CommandLog
                                )
                in
                let
                    initialSnapshots =
                        namedTests
                            |> List.drop initialTestIndex
                            |> List.head
                            |> Maybe.map .snapshots
                            |> Maybe.withDefault []

                    initialStepIndex =
                        resolveStepFromUrl url initialSnapshots
                in
                ( { tests = namedTests
                  , currentTestIndex = initialTestIndex
                  , currentStepIndex = initialStepIndex
                  , hoveredStepIndex = Nothing
                  , showModel = False
                  , sidebarMode = initialMode
                  , navKey = key
                  , basePath = basePath
                  , searchQuery = ""
                  , viewportWidth = Nothing
                  , showEffects = False
                  , showNetwork = False
                  , showNetworkBackend = True
                  , showNetworkFrontend = True
                  , showFetchers = False
                  , showCookies = False
                  , previewMode = After
                  , expandedGroups = defaultExpandedGroups initialSnapshots
                  , modelTreeExpanded = Set.empty
                  }
                , Cmd.none
                )
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onKeyDown
        (Decode.field "key" Decode.string
            |> Decode.map KeyDown
        )


scrollToStep : Int -> Cmd Msg
scrollToStep index =
    Browser.Dom.getElement ("step-" ++ String.fromInt index)
        |> Task.andThen
            (\stepEl ->
                Browser.Dom.getElement "sidebar-steps"
                    |> Task.andThen
                        (\containerEl ->
                            Browser.Dom.getViewportOf "sidebar-steps"
                                |> Task.andThen
                                    (\viewport ->
                                        let
                                            stepTop =
                                                stepEl.element.y - containerEl.element.y + viewport.viewport.y

                                            stepBottom =
                                                stepTop + stepEl.element.height

                                            viewTop =
                                                viewport.viewport.y

                                            viewBottom =
                                                viewTop + viewport.viewport.height
                                        in
                                        if stepTop < viewTop then
                                            Browser.Dom.setViewportOf "sidebar-steps" 0 (stepTop - 8)

                                        else if stepBottom > viewBottom then
                                            Browser.Dom.setViewportOf "sidebar-steps" 0 (stepBottom - viewport.viewport.height + 8)

                                        else
                                            Task.succeed ()
                                    )
                        )
            )
        |> Task.attempt (\_ -> NoOp)


{-| Extract the base path (e.g., "/_tests") from the initial URL.
This is everything up to and including the viewer route prefix.
-}
extractBasePath : Url -> String
extractBasePath url =
    let
        path =
            url.path
    in
    if String.contains "/_tests" path then
        let
            idx =
                String.indexes "/_tests" path
                    |> List.head
                    |> Maybe.withDefault 0
        in
        String.left (idx + String.length "/_tests") path

    else
        path


{-| Extract the test name from the URL path after the base path.
e.g., "/_tests/FrameworkTests.counterClicksTest" -> Just "FrameworkTests.counterClicksTest"
-}
extractTestName : String -> Url -> Maybe String
extractTestName basePath url =
    let
        rest =
            String.dropLeft (String.length basePath) url.path
                |> String.dropLeft 1
    in
    if String.isEmpty rest then
        Nothing

    else
        Just rest


findTestIndex : String -> List NamedTest -> Maybe Int
findTestIndex name tests =
    tests
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, t ) -> t.name == name)
        |> List.head
        |> Maybe.map Tuple.first


{-| If a test has an ERROR step, return its index so we can auto-navigate to it.
-}
errorStepIndex : NamedTest -> Maybe Int
errorStepIndex test =
    test.snapshots
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, s ) -> s.stepKind == Error)
        |> List.head
        |> Maybe.map Tuple.first


{-| Get the initial step index for a test -- jump to error if one exists.
-}
initialStepForTest : List NamedTest -> Int -> Int
initialStepForTest tests testIndex =
    tests
        |> List.drop testIndex
        |> List.head
        |> Maybe.andThen errorStepIndex
        |> Maybe.withDefault 0


{-| Resolve a step index from URL query params with best-effort matching.

1. If step N still has the saved label -- exact match
2. If step N has a different label -- find nearest step with that label
3. If no steps match the label -- clamp to step N anyway

-}
resolveStepFromUrl : Url -> List Snapshot -> Int
resolveStepFromUrl url snapshots =
    let
        params =
            parseQueryParams url

        maybeStep =
            params
                |> List.filter (\( k, _ ) -> k == "step")
                |> List.head
                |> Maybe.andThen (\( _, v ) -> String.toInt v)

        maybeLabel =
            params
                |> List.filter (\( k, _ ) -> k == "at")
                |> List.head
                |> Maybe.map Tuple.second
                |> Maybe.andThen Url.percentDecode
    in
    case maybeStep of
        Nothing ->
            -- No step in URL, use default (error step or 0)
            snapshots
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, s ) -> s.stepKind == Error)
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault 0

        Just stepIdx ->
            let
                clamped =
                    clamp 0 (List.length snapshots - 1) stepIdx
            in
            case maybeLabel of
                Nothing ->
                    clamped

                Just label ->
                    -- Check if step at saved index still has the same label
                    let
                        labelAtIndex =
                            snapshots
                                |> List.drop clamped
                                |> List.head
                                |> Maybe.map .label
                    in
                    if labelAtIndex == Just label then
                        -- Exact match at expected index
                        clamped

                    else
                        -- Label shifted. Find nearest step with that label.
                        let
                            candidates =
                                snapshots
                                    |> List.indexedMap Tuple.pair
                                    |> List.filter (\( _, s ) -> s.label == label)

                            nearest =
                                candidates
                                    |> List.sortBy (\( i, _ ) -> abs (i - clamped))
                                    |> List.head
                        in
                        case nearest of
                            Just ( i, _ ) ->
                                i

                            Nothing ->
                                -- Label gone entirely, fall back to index
                                clamped


parseQueryParams : Url -> List ( String, String )
parseQueryParams url =
    case url.query of
        Nothing ->
            []

        Just q ->
            q
                |> String.split "&"
                |> List.filterMap
                    (\pair ->
                        case String.split "=" pair of
                            [ k, v ] ->
                                Just ( k, v )

                            _ ->
                                Nothing
                    )


{-| Update the URL to reflect the current step position. Uses replaceUrl
so step changes don't create new browser history entries.
-}
syncStepToUrl : Model -> Int -> Cmd Msg
syncStepToUrl model stepIndex =
    let
        testName =
            model.tests
                |> List.drop model.currentTestIndex
                |> List.head
                |> Maybe.map .name

        label =
            currentSnapshots model
                |> List.drop stepIndex
                |> List.head
                |> Maybe.map .label
    in
    case testName of
        Just name ->
            Nav.replaceUrl model.navKey
                (buildTestUrl model (Just name) (Maybe.map (\l -> ( stepIndex, l )) label))

        Nothing ->
            Cmd.none


buildTestUrl : Model -> Maybe String -> Maybe ( Int, String ) -> String
buildTestUrl model maybeName maybeStep =
    let
        basePart =
            case maybeName of
                Just name ->
                    model.basePath ++ "/" ++ name

                Nothing ->
                    model.basePath

        queryPart =
            case maybeStep of
                Just ( idx, label ) ->
                    "?step=" ++ String.fromInt idx ++ "&at=" ++ Url.percentEncode label

                Nothing ->
                    ""
    in
    basePart ++ queryPart


{-| Push a new URL for test navigation (creates browser history entry).
-}
pushTestUrl : Model -> Maybe String -> Cmd Msg
pushTestUrl model maybeName =
    Nav.pushUrl model.navKey (buildTestUrl model maybeName Nothing)


{-| Push URL with step info for test navigation (creates history entry).
-}
pushTestUrlWithStep : Model -> Maybe String -> Maybe ( Int, String ) -> Cmd Msg
pushTestUrlWithStep model maybeName maybeStep =
    Nav.pushUrl model.navKey (buildTestUrl model maybeName maybeStep)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NextStep ->
            let
                snapshots =
                    currentSnapshots model

                newIndex =
                    nextParentStep model.currentStepIndex (List.length snapshots - 1) snapshots

                newModel =
                    { model | currentStepIndex = newIndex, previewMode = defaultPreviewMode snapshots newIndex }
            in
            ( newModel
            , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex ]
            )

        PrevStep ->
            let
                snapshots =
                    currentSnapshots model

                newIndex =
                    prevParentStep model.currentStepIndex snapshots

                newModel =
                    { model | currentStepIndex = newIndex, previewMode = defaultPreviewMode snapshots newIndex }
            in
            ( newModel
            , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex ]
            )

        GoToStep index ->
            let
                snapshots =
                    currentSnapshots model

                newIndex =
                    clamp 0 (List.length snapshots - 1) index

                newModel =
                    { model | currentStepIndex = newIndex, previewMode = defaultPreviewMode snapshots newIndex }
            in
            ( newModel
            , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex ]
            )

        NextTest ->
            if List.length model.tests <= 1 then
                ( model, Cmd.none )

            else
                let
                    newIndex =
                        modBy (List.length model.tests) (model.currentTestIndex + 1)

                    newTest =
                        model.tests |> List.drop newIndex |> List.head

                    testName =
                        newTest |> Maybe.map .name

                    newSnapshots =
                        newTest |> Maybe.map .snapshots |> Maybe.withDefault []
                in
                ( { model
                    | currentTestIndex = newIndex
                    , currentStepIndex = 0
                    , hoveredStepIndex = Nothing
                    , expandedGroups = defaultExpandedGroups newSnapshots
                  }
                , Cmd.batch [ scrollToStep 0, pushTestUrl model testName ]
                )

        PrevTest ->
            if List.length model.tests <= 1 then
                ( model, Cmd.none )

            else
                let
                    newIndex =
                        modBy (List.length model.tests) (model.currentTestIndex - 1 + List.length model.tests)

                    newTest =
                        model.tests |> List.drop newIndex |> List.head

                    testName =
                        newTest |> Maybe.map .name

                    newSnapshots =
                        newTest |> Maybe.map .snapshots |> Maybe.withDefault []
                in
                ( { model
                    | currentTestIndex = newIndex
                    , currentStepIndex = 0
                    , hoveredStepIndex = Nothing
                    , expandedGroups = defaultExpandedGroups newSnapshots
                  }
                , Cmd.batch [ scrollToStep 0, pushTestUrl model testName ]
                )

        GoToTest index ->
            let
                clampedIndex =
                    clamp 0 (List.length model.tests - 1) index

                test =
                    model.tests |> List.drop clampedIndex |> List.head

                testName =
                    test |> Maybe.map .name

                stepIndex =
                    initialStepForTest model.tests clampedIndex

                stepLabel =
                    test
                        |> Maybe.andThen (\t -> t.snapshots |> List.drop stepIndex |> List.head)
                        |> Maybe.map .label

                newSnapshots =
                    test |> Maybe.map .snapshots |> Maybe.withDefault []
            in
            ( { model
                | currentTestIndex = clampedIndex
                , currentStepIndex = stepIndex
                , hoveredStepIndex = Nothing
                , sidebarMode = CommandLog
                , expandedGroups = defaultExpandedGroups newSnapshots
              }
            , Cmd.batch
                [ scrollToStep stepIndex
                , pushTestUrlWithStep model testName (Maybe.map (\l -> ( stepIndex, l )) stepLabel)
                ]
            )

        HoverStep index ->
            ( { model | hoveredStepIndex = Just index }, Cmd.none )

        UnhoverStep ->
            ( { model | hoveredStepIndex = Nothing }, Cmd.none )

        ShowTestList ->
            ( { model | sidebarMode = TestList, hoveredStepIndex = Nothing, searchQuery = "" }
            , pushTestUrl model Nothing
            )

        ToggleModel ->
            ( { model | showModel = not model.showModel }, Cmd.none )

        ToggleGroup parentIndex ->
            ( { model
                | expandedGroups =
                    if Set.member parentIndex model.expandedGroups then
                        Set.remove parentIndex model.expandedGroups

                    else
                        Set.insert parentIndex model.expandedGroups
              }
            , Cmd.none
            )

        ToggleModelNode path ->
            ( { model
                | modelTreeExpanded =
                    if Set.member path model.modelTreeExpanded then
                        Set.remove path model.modelTreeExpanded

                    else
                        Set.insert path model.modelTreeExpanded
              }
            , Cmd.none
            )

        ToggleEffects ->
            ( { model | showEffects = not model.showEffects }, Cmd.none )

        ToggleNetwork ->
            ( { model | showNetwork = not model.showNetwork }, Cmd.none )

        ToggleNetworkBackend ->
            ( { model | showNetworkBackend = not model.showNetworkBackend }, Cmd.none )

        ToggleNetworkFrontend ->
            ( { model | showNetworkFrontend = not model.showNetworkFrontend }, Cmd.none )

        ToggleFetchers ->
            ( { model | showFetchers = not model.showFetchers }, Cmd.none )

        ToggleCookies ->
            ( { model | showCookies = not model.showCookies }, Cmd.none )

        SetPreviewMode mode ->
            ( { model | previewMode = mode }, Cmd.none )

        KeyDown key ->
            case key of
                "ArrowRight" ->
                    if model.sidebarMode == CommandLog then
                        let
                            snapshots =
                                currentSnapshots model

                            numChildren =
                                childCount model.currentStepIndex snapshots

                            isGroupParent =
                                not (isChildStep model.currentStepIndex snapshots) && numChildren > 0
                        in
                        if isGroupParent && not (Set.member model.currentStepIndex model.expandedGroups) then
                            update (ToggleGroup model.currentStepIndex) model

                        else
                            ( model, Cmd.none )

                    else
                        ( model, Cmd.none )

                "ArrowLeft" ->
                    if model.sidebarMode == CommandLog then
                        let
                            snapshots =
                                currentSnapshots model

                            numChildren =
                                childCount model.currentStepIndex snapshots

                            isGroupParent =
                                not (isChildStep model.currentStepIndex snapshots) && numChildren > 0

                            isChild =
                                isChildStep model.currentStepIndex snapshots
                        in
                        if isGroupParent && Set.member model.currentStepIndex model.expandedGroups then
                            update (ToggleGroup model.currentStepIndex) model

                        else if isChild then
                            let
                                parentIdx =
                                    parentOfChild model.currentStepIndex snapshots
                            in
                            ( { model
                                | currentStepIndex = parentIdx
                                , expandedGroups = Set.remove parentIdx model.expandedGroups
                              }
                            , scrollToStep parentIdx
                            )

                        else
                            ( model, Cmd.none )

                    else
                        ( model, Cmd.none )

                "ArrowDown" ->
                    if model.sidebarMode == TestList then
                        update NextTest model

                    else
                        let
                            snapshots =
                                currentSnapshots model

                            newIndex =
                                nextVisibleStep model.currentStepIndex (List.length snapshots - 1) snapshots model.expandedGroups

                            newModel =
                                { model | currentStepIndex = newIndex, previewMode = defaultPreviewMode snapshots newIndex }
                        in
                        ( newModel
                        , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex ]
                        )

                "ArrowUp" ->
                    if model.sidebarMode == TestList then
                        update PrevTest model

                    else
                        let
                            snapshots =
                                currentSnapshots model

                            newIndex =
                                prevVisibleStep model.currentStepIndex snapshots model.expandedGroups

                            newModel =
                                { model | currentStepIndex = newIndex, previewMode = defaultPreviewMode snapshots newIndex }
                        in
                        ( newModel
                        , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex ]
                        )

                "Escape" ->
                    if List.length model.tests > 1 then
                        update ShowTestList model

                    else
                        ( model, Cmd.none )

                "m" ->
                    update ToggleModel model

                "e" ->
                    update ToggleEffects model

                "n" ->
                    update ToggleNetwork model

                "f" ->
                    update ToggleFetchers model

                "c" ->
                    update ToggleCookies model

                _ ->
                    ( model, Cmd.none )

        UpdateSearch query ->
            ( { model | searchQuery = query }, Cmd.none )

        SetViewport width ->
            ( { model | viewportWidth = width }, Cmd.none )

        UrlChanged url ->
            let
                testName =
                    extractTestName model.basePath url
            in
            case testName of
                Just name ->
                    case findTestIndex name model.tests of
                        Just idx ->
                            let
                                snapshots =
                                    model.tests
                                        |> List.drop idx
                                        |> List.head
                                        |> Maybe.map .snapshots
                                        |> Maybe.withDefault []

                                stepIndex =
                                    resolveStepFromUrl url snapshots
                            in
                            ( { model
                                | currentTestIndex = idx
                                , currentStepIndex = stepIndex
                                , hoveredStepIndex = Nothing
                                , sidebarMode = CommandLog
                                , expandedGroups =
                                    if idx == model.currentTestIndex then
                                        model.expandedGroups

                                    else
                                        Set.empty
                              }
                            , scrollToStep stepIndex
                            )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    if List.length model.tests > 1 then
                        ( { model
                            | sidebarMode = TestList
                            , hoveredStepIndex = Nothing
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.navKey (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        NoOp ->
            ( model, Cmd.none )



-- HELPERS


currentSnapshots : Model -> List Snapshot
currentSnapshots model =
    model.tests
        |> List.drop model.currentTestIndex
        |> List.head
        |> Maybe.map .snapshots
        |> Maybe.withDefault []


currentSnapshotCount : Model -> Int
currentSnapshotCount model =
    List.length (currentSnapshots model)


{-| Interaction steps default to Before (so the user sees the element they
clicked), all other step kinds default to After.
-}
defaultPreviewMode : List Snapshot -> Int -> PreviewMode
defaultPreviewMode snapshots index =
    case snapshots |> List.drop index |> List.head of
        Just snapshot ->
            if snapshot.stepKind == Interaction && snapshot.targetElement /= Nothing then
                Before

            else
                After

        Nothing ->
            After


displayedStepIndex : Model -> Int
displayedStepIndex model =
    model.hoveredStepIndex |> Maybe.withDefault model.currentStepIndex


displayedSnapshot : Model -> Maybe Snapshot
displayedSnapshot model =
    model.tests
        |> List.drop model.currentTestIndex
        |> List.head
        |> Maybe.andThen
            (\test ->
                test.snapshots
                    |> List.drop (displayedStepIndex model)
                    |> List.head
            )


currentTestName : Model -> String
currentTestName model =
    model.tests
        |> List.drop model.currentTestIndex
        |> List.head
        |> Maybe.map .name
        |> Maybe.withDefault ""


testHasError : NamedTest -> Bool
testHasError test =
    test.snapshots
        |> List.any (\s -> s.stepKind == Error)


stepKindColor : Snapshot -> String
stepKindColor snapshot =
    Icons.kindColor (Icons.kindFromSnapshot snapshot)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "elm-pages Test Viewer"
    , body =
        [ Html.node "style" [] [ Html.text css ]
        , Html.div [ Attr.class "viewer" ]
            [ viewHeader model
            , Html.div [ Attr.class "viewer-body" ]
                [ viewSidebar model
                , viewMainPanel model
                , if model.showNetwork then
                    viewNetworkSidebar model
                        (displayedStepIndex model)
                        (currentSnapshots model)

                  else
                    Html.text ""
                , if model.showCookies then
                    viewCookieSidebar
                        (displayedStepIndex model)
                        (currentSnapshots model)

                  else
                    Html.text ""
                ]
            ]
        ]
    }


viewHeader : Model -> Html Msg
viewHeader model =
    let
        passCount =
            model.tests |> List.filter (\t -> not (testHasError t)) |> List.length

        failCount =
            List.length model.tests - passCount
    in
    Html.div [ Attr.class "viewer-header" ]
        [ Html.div [ Attr.class "header-left" ]
            [ Html.span [ Attr.class "header-logo" ] [ Html.text "elm-pages" ]
            , Html.span [ Attr.class "header-title" ] [ Html.text " Test Viewer" ]
            ]
        , Html.div [ Attr.class "header-center" ]
            [ case model.sidebarMode of
                TestList ->
                    Html.span [ Attr.class "header-summary" ]
                        [ Html.span [ Attr.style "color" "#7ee787" ]
                            [ Html.text (String.fromInt passCount ++ " passed") ]
                        , if failCount > 0 then
                            Html.span []
                                [ Html.text "  "
                                , Html.span [ Attr.style "color" "#e74c3c" ]
                                    [ Html.text (String.fromInt failCount ++ " failed") ]
                                ]

                          else
                            Html.text ""
                        ]

                CommandLog ->
                    Html.span [ Attr.class "test-name" ]
                        [ Html.text (currentTestName model) ]
            ]
        , Html.div [ Attr.class "header-right" ]
            [ case model.sidebarMode of
                CommandLog ->
                    Html.span [ Attr.class "step-counter" ]
                        [ Html.text
                            ("Step "
                                ++ String.fromInt (model.currentStepIndex + 1)
                                ++ " / "
                                ++ String.fromInt (currentSnapshotCount model)
                            )
                        ]

                TestList ->
                    Html.text ""
            , viewViewportPicker model.viewportWidth
            , Html.button
                [ Attr.classList
                    [ ( "toggle-button", True )
                    , ( "toggle-active", model.showNetwork )
                    ]
                , Html.Events.onClick ToggleNetwork
                ]
                [ Html.text "Network" ]
            , Html.button
                [ Attr.classList
                    [ ( "toggle-button", True )
                    , ( "toggle-active", model.showFetchers )
                    ]
                , Html.Events.onClick ToggleFetchers
                ]
                [ Html.text "Fetchers" ]
            , Html.button
                [ Attr.classList
                    [ ( "toggle-button", True )
                    , ( "toggle-active", model.showCookies )
                    ]
                , Html.Events.onClick ToggleCookies
                ]
                [ Html.text "Cookies" ]
            , Html.button
                [ Attr.classList
                    [ ( "toggle-button", True )
                    , ( "toggle-active", model.showEffects )
                    ]
                , Html.Events.onClick ToggleEffects
                ]
                [ Html.text "Effects" ]
            , Html.button
                [ Attr.classList
                    [ ( "toggle-button", True )
                    , ( "toggle-active", model.showModel )
                    ]
                , Html.Events.onClick ToggleModel
                ]
                [ Html.text "Model" ]
            ]
        ]


viewViewportPicker : Maybe Int -> Html Msg
viewViewportPicker current =
    let
        sizes =
            [ ( Nothing, "Full" )
            , ( Just 1280, "1280" )
            , ( Just 768, "768" )
            , ( Just 375, "375" )
            ]
    in
    Html.div [ Attr.class "viewport-picker" ]
        (sizes
            |> List.map
                (\( width, label ) ->
                    Html.button
                        [ Attr.classList
                            [ ( "viewport-btn", True )
                            , ( "viewport-btn-active", current == width )
                            ]
                        , Html.Events.onClick (SetViewport width)
                        ]
                        [ Html.text label ]
                )
        )


viewSidebar : Model -> Html Msg
viewSidebar model =
    case model.sidebarMode of
        TestList ->
            viewTestListSidebar model

        CommandLog ->
            viewCommandLogSidebar model


viewTestListSidebar : Model -> Html Msg
viewTestListSidebar model =
    let
        filteredTests =
            if String.isEmpty model.searchQuery then
                model.tests |> List.indexedMap Tuple.pair

            else
                let
                    q =
                        String.toLower model.searchQuery
                in
                model.tests
                    |> List.indexedMap Tuple.pair
                    |> List.filter (\( _, t ) -> String.contains q (String.toLower t.name))
    in
    Html.div [ Attr.class "sidebar" ]
        [ Html.div [ Attr.class "sidebar-header" ]
            [ Html.span [ Attr.class "sidebar-title" ]
                [ Html.text
                    (String.fromInt (List.length model.tests) ++ " Tests")
                ]
            , if List.length model.tests > 3 then
                Html.input
                    [ Attr.class "search-input"
                    , Attr.placeholder "Filter tests..."
                    , Attr.value model.searchQuery
                    , Html.Events.onInput UpdateSearch
                    ]
                    []

              else
                Html.text ""
            ]
        , Html.div [ Attr.class "sidebar-steps", Attr.id "sidebar-steps" ]
            (filteredTests
                |> List.map
                    (\( i, test ) ->
                        let
                            hasError =
                                testHasError test

                            stepCount =
                                List.length test.snapshots

                            isSelected =
                                i == model.currentTestIndex
                        in
                        Html.div
                            [ Attr.classList
                                [ ( "test-list-row", True )
                                , ( "test-list-row-selected", isSelected )
                                , ( "test-list-row-error", hasError )
                                ]
                            , Html.Events.onClick (GoToTest i)
                            ]
                            [ Html.span
                                [ Attr.class "test-list-indicator"
                                , Attr.style "color"
                                    (if hasError then
                                        "#e74c3c"

                                     else
                                        "#7ee787"
                                    )
                                ]
                                [ Html.text
                                    (if hasError then
                                        "x"

                                     else
                                        "o"
                                    )
                                ]
                            , Html.div [ Attr.class "test-list-info" ]
                                [ Html.div [ Attr.class "test-list-name", Attr.title test.name ] [ Html.text test.name ]
                                , Html.div [ Attr.class "test-list-meta" ]
                                    [ Html.text (String.fromInt stepCount ++ " steps") ]
                                ]
                            ]
                    )
            )
        ]


viewCommandLogSidebar : Model -> Html Msg
viewCommandLogSidebar model =
    let
        snapshots =
            currentSnapshots model

        isHovering =
            model.hoveredStepIndex /= Nothing

        errorIndex =
            snapshots
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, s ) -> s.stepKind == Error)
                |> List.head
                |> Maybe.map Tuple.first

        failureCauseIndex =
            errorIndex |> Maybe.map (\ei -> ei - 1)
    in
    Html.div [ Attr.class "sidebar" ]
        [ Html.div [ Attr.class "sidebar-header" ]
            (if List.length model.tests > 1 then
                [ Html.button
                    [ Attr.class "sidebar-back"
                    , Html.Events.onClick ShowTestList
                    ]
                    [ Html.text "< All Tests" ]
                , Html.span [ Attr.class "sidebar-title" ]
                    [ Html.text (currentTestName model) ]
                ]

             else
                [ Html.span [ Attr.class "sidebar-title" ] [ Html.text "Command Log" ]
                ]
            )
        , Html.div [ Attr.class "sidebar-steps", Attr.id "sidebar-steps" ]
            (let
                namedGroupStartSet =
                    computeNamedGroupStarts snapshots
             in
             snapshots
                |> List.indexedMap Tuple.pair
                |> List.concatMap
                    (\( i, snapshot ) ->
                        let
                            isChild =
                                isChildStep i snapshots

                            numChildren =
                                childCount i snapshots

                            isGroupParent =
                                not isChild && numChildren > 0 && snapshot.stepKind /= Assertion

                            isExpanded =
                                Set.member i model.expandedGroups

                            isHiddenChild =
                                isChild && not (Set.member (parentOfChild i snapshots) model.expandedGroups)

                            isNamedGroupStart =
                                Set.member i namedGroupStartSet

                            namedGroupKey =
                                -(i + 1)

                            isNamedGroupExpanded =
                                Set.member namedGroupKey model.expandedGroups

                            hiddenByGroup =
                                isHiddenByNamedGroup i snapshots model.expandedGroups

                            groupHeader =
                                if isNamedGroupStart then
                                    [ viewNamedGroupHeader i
                                        (Maybe.withDefault "" snapshot.groupLabel)
                                        isNamedGroupExpanded
                                        (namedGroupChildCount i snapshots)
                                    ]

                                else
                                    []

                            stepRow =
                                if isHiddenChild || hiddenByGroup then
                                    []

                                else
                                    let
                                        previousSnapshot =
                                            if i > 0 then
                                                snapshots |> List.drop (i - 1) |> List.head

                                            else
                                                Nothing

                                        events =
                                            computeStepEvents i snapshot previousSnapshot

                                        eventDots =
                                            viewStepEventDots model events
                                    in
                                    [ viewStepRow i snapshot model.currentStepIndex isHovering (model.hoveredStepIndex == Just i) (failureCauseIndex == Just i) isChild isGroupParent isExpanded numChildren eventDots ]
                        in
                        groupHeader ++ stepRow
                    )
            )
        ]


viewStepRow : Int -> Snapshot -> Int -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Int -> Html Msg -> Html Msg
viewStepRow index snapshot currentIndex isHovering isHovered isFailureCause isChild isGroupParent isExpanded numChildren eventDots =
    let
        isActive =
            index == currentIndex

        isPast =
            index < currentIndex

        kindColor =
            stepKindColor snapshot
    in
    Html.div
        [ Attr.classList
            [ ( "step-row", True )
            , ( "step-row-active", isActive && not isHovering )
            , ( "step-row-hovered", isHovered )
            , ( "step-row-past", isPast && not isActive )
            , ( "step-row-error", snapshot.stepKind == Error )
            , ( "step-row-failure-cause", isFailureCause )
            , ( "step-row-child", isChild )
            ]
        , Attr.id ("step-" ++ String.fromInt index)
        , Html.Events.onClick (GoToStep index)
        , Html.Events.onMouseEnter (HoverStep index)
        , Html.Events.onMouseLeave UnhoverStep
        ]
        [ Html.span [ Attr.class "step-number" ]
            [ Html.text (String.fromInt (index + 1)) ]
        , Html.span
            [ Attr.class "step-icon"
            , Attr.style "color" kindColor
            ]
            [ Icons.stepKind snapshot ]
        , Html.span [ Attr.class "step-label", Attr.title snapshot.label ]
            (viewStepLabel snapshot)
        , eventDots
        , if isGroupParent then
            Html.span
                [ Attr.class "step-group-toggle"
                , Html.Events.stopPropagationOn "click"
                    (Decode.succeed ( ToggleGroup index, True ))
                ]
                [ Html.text
                    (if isExpanded then
                        String.fromInt numChildren ++ " ▾"

                     else
                        String.fromInt numChildren ++ " ▸"
                    )
                ]

          else
            Html.text ""
        ]


{-| A per-step count of events on each channel, used to render the right-edge dots.
-}
type alias StepEvents =
    { networkBackend : Int
    , networkFrontend : Int
    , fetcher : Int
    , cookie : Int
    , effect : Int
    }


{-| Count event-channel activity introduced at this step. Uses `stepIndex` on
`NetworkEntry` for the network split; diffs `fetcherLog` / `cookieLog` /
`pendingEffects` against the previous snapshot for the other channels.
-}
computeStepEvents : Int -> Snapshot -> Maybe Snapshot -> StepEvents
computeStepEvents index snapshot previous =
    let
        newNetwork =
            snapshot.networkLog
                |> List.filter (\e -> e.stepIndex == index)

        networkBackend =
            newNetwork
                |> List.filter (\e -> e.source == Backend)
                |> List.length

        networkFrontend =
            newNetwork
                |> List.filter (\e -> e.source == Frontend)
                |> List.length

        prevFetcherSigs =
            case previous of
                Just prev ->
                    prev.fetcherLog |> List.map fetcherSig

                Nothing ->
                    []

        fetcher =
            snapshot.fetcherLog
                |> List.map fetcherSig
                |> List.filter (\sig -> not (List.member sig prevFetcherSigs))
                |> List.length

        prevCookieSigs =
            case previous of
                Just prev ->
                    prev.cookieLog |> List.map cookieSig

                Nothing ->
                    []

        cookie =
            snapshot.cookieLog
                |> List.map cookieSig
                |> List.filter (\sig -> not (List.member sig prevCookieSigs))
                |> List.length

        prevEffects =
            case previous of
                Just prev ->
                    prev.pendingEffects

                Nothing ->
                    []

        added =
            snapshot.pendingEffects
                |> List.filter (\e -> not (List.member e prevEffects))
                |> List.length

        resolved =
            prevEffects
                |> List.filter (\e -> not (List.member e snapshot.pendingEffects))
                |> List.length
    in
    { networkBackend = networkBackend
    , networkFrontend = networkFrontend
    , fetcher = fetcher
    , cookie = cookie
    , effect = added + resolved
    }


fetcherSig : FetcherEntry -> String
fetcherSig f =
    f.id ++ "|" ++ fetcherStatusString f.status


fetcherStatusString : FetcherStatus -> String
fetcherStatusString status =
    case status of
        FetcherSubmitting ->
            "submitting"

        FetcherReloading ->
            "reloading"

        FetcherComplete ->
            "complete"


cookieSig : ( String, CookieEntry ) -> String
cookieSig ( name, entry ) =
    name ++ "=" ++ entry.value


{-| Render the right-edge event dots. Hidden channels respect the same
show-flags the toolbar uses, so toggling a channel off declutters the rail.
A zero event count renders nothing.
-}
viewStepEventDots : Model -> StepEvents -> Html Msg
viewStepEventDots model events =
    let
        networkBackendColor =
            "#7dd3fc"

        networkFrontendColor =
            "#38bdf8"

        fetcherColor =
            "#86efac"

        cookieColor =
            "#fcd34d"

        effectColor =
            "#c4b5fd"

        dot : Int -> String -> String -> Html Msg -> Html Msg
        dot count label title icon =
            if count <= 0 then
                Html.text ""

            else
                Html.span
                    [ Attr.class "step-event-dot"
                    , Attr.title (String.fromInt count ++ " " ++ title)
                    , Attr.style "color" label
                    ]
                    [ icon
                    , if count > 1 then
                        Html.span [ Attr.class "step-event-count" ]
                            [ Html.text (String.fromInt count) ]

                      else
                        Html.text ""
                    ]

        dots =
            [ if model.showNetworkBackend then
                dot events.networkBackend networkBackendColor "backend network event" (Icons.eventNetwork networkBackendColor)

              else
                Html.text ""
            , if model.showNetworkFrontend then
                dot events.networkFrontend networkFrontendColor "frontend network event" (Icons.eventNetwork networkFrontendColor)

              else
                Html.text ""
            , if model.showFetchers then
                dot events.fetcher fetcherColor "fetcher event" (Icons.eventFetcher fetcherColor)

              else
                Html.text ""
            , if model.showCookies then
                dot events.cookie cookieColor "cookie event" (Icons.eventCookie cookieColor)

              else
                Html.text ""
            , if model.showEffects then
                dot events.effect effectColor "effect" (Icons.eventEffect effectColor)

              else
                Html.text ""
            ]
    in
    Html.span [ Attr.class "step-event-dots" ] dots


{-| Render a step label with structured formatting.
For any step whose label starts with a recognized verb, the verb is dimmed and
the remaining detail (target, selector, URL, ...) is highlighted. Falls back to
the raw label.
-}
viewStepLabel : Snapshot -> List (Html Msg)
viewStepLabel snapshot =
    case splitAssertionLabel snapshot.label of
        Just { fnName, selectorDetail, withinScope } ->
            [ Html.span [ Attr.class "step-label-fn" ] [ Html.text (fnName ++ " ") ]
            , Html.span [ Attr.class "step-label-selector" ] [ Html.text selectorDetail ]
            ]
                ++ (case withinScope of
                        Just scope ->
                            [ Html.span [ Attr.class "step-label-scope" ] [ Html.text (" " ++ scope) ] ]

                        Nothing ->
                            []
                   )

        Nothing ->
            [ Html.text snapshot.label ]


{-| Split a step label into a dim verb + highlighted target, honoring an optional
trailing `(within ...)` scope. Recognizes assertion prefixes as well as the
common interaction / setup / navigation verbs that appear on the step rail.
-}
splitAssertionLabel : String -> Maybe { fnName : String, selectorDetail : String, withinScope : Maybe String }
splitAssertionLabel label =
    let
        prefixes =
            [ "ensureViewHas "
            , "ensureViewHasNot "
            , "ensureView"
            , "ensureBrowserUrl "
            , "expectViewHas "
            , "expectViewHasNot "
            , "clickButtonWith "
            , "clickButton "
            , "clickLinkByText "
            , "clickLinkWith "
            , "clickLink "
            , "selectOption "
            , "check "
            , "uncheck "
            , "fillIn "
            , "fillInTextarea "
            , "simulateHttpPost "
            , "simulateHttpGet "
            , "simulateCustom "
            , "simulateCommand "
            , "navigateTo "
            , "redirected "
            , "redirected→"
            ]

        tryPrefix prefix =
            if String.startsWith prefix label then
                let
                    rest =
                        String.dropLeft (String.length prefix) label

                    ( selectorPart, scopePart ) =
                        case findWithinScope rest of
                            Just ( sel, scope ) ->
                                ( sel, Just scope )

                            Nothing ->
                                ( rest, Nothing )
                in
                Just
                    { fnName = String.trimRight prefix
                    , selectorDetail = selectorPart
                    , withinScope = scopePart
                    }

            else
                Nothing
    in
    firstJust tryPrefix prefixes


{-| Extract "(within ...)" suffix from a label string.
Returns (selector part, within part) if found.
-}
findWithinScope : String -> Maybe ( String, String )
findWithinScope str =
    let
        marker =
            " (within "
    in
    case String.indices marker str of
        [] ->
            Nothing

        idx :: _ ->
            Just
                ( String.left idx str
                , String.dropLeft idx str
                )


firstJust : (a -> Maybe b) -> List a -> Maybe b
firstJust f list =
    case list of
        [] ->
            Nothing

        x :: rest ->
            case f x of
                Just result ->
                    Just result

                Nothing ->
                    firstJust f rest


viewMainPanel : Model -> Html Msg
viewMainPanel model =
    let
        previousSnapshot : Maybe Snapshot
        previousSnapshot =
            let
                idx =
                    displayedStepIndex model - 1
            in
            if idx >= 0 then
                model.tests
                    |> List.drop model.currentTestIndex
                    |> List.head
                    |> Maybe.andThen
                        (\test ->
                            test.snapshots
                                |> List.drop idx
                                |> List.head
                        )

            else
                Nothing
    in
    Html.div [ Attr.class "main-panel" ]
        [ case displayedSnapshot model of
            Just snapshot ->
                case snapshot.errorMessage of
                    Just errorMsg ->
                        Html.div [ Attr.class "main-panel-content" ]
                            [ viewUrlBar
                                (previousSnapshot
                                    |> Maybe.withDefault snapshot
                                )
                            , viewErrorPanel errorMsg
                            , case previousSnapshot of
                                Just prev ->
                                    viewRenderedPageWithWidth model.viewportWidth prev

                                Nothing ->
                                    viewEmptyRenderedPage
                            , if model.showFetchers then
                                viewFetcherInspector (displayedStepIndex model) (currentSnapshots model)

                              else
                                Html.text ""
                            , if model.showEffects then
                                viewEffectInspector
                                    (previousSnapshot
                                        |> Maybe.withDefault snapshot
                                    )

                              else
                                Html.text ""
                            , if model.showModel then
                                viewModelInspector model.modelTreeExpanded
                                    (previousSnapshot
                                        |> Maybe.withDefault snapshot
                                    )

                              else
                                Html.text ""
                            ]

                    Nothing ->
                        let
                            previewSnapshot =
                                case model.previewMode of
                                    Before ->
                                        case previousSnapshot of
                                            Just prev ->
                                                { prev | targetElement = snapshot.targetElement }

                                            Nothing ->
                                                snapshot

                                    After ->
                                        snapshot

                            hasPrevious =
                                previousSnapshot /= Nothing

                            isStartStep =
                                displayedStepIndex model == 0
                        in
                        Html.div [ Attr.class "main-panel-content" ]
                            [ Html.div [ Attr.class "url-bar-row" ]
                                [ viewUrlBar previewSnapshot
                                , if not isStartStep && hasPrevious then
                                    viewBeforeAfterToggle model.previewMode

                                  else
                                    Html.text ""
                                ]
                            , viewRenderedPageWithOptions model.viewportWidth
                                (if hasPrevious && not isStartStep then
                                    Just model.previewMode

                                 else
                                    Nothing
                                )
                                previewSnapshot
                            , if model.showFetchers then
                                viewFetcherInspector (displayedStepIndex model) (currentSnapshots model)

                              else
                                Html.text ""
                            , if model.showEffects then
                                viewEffectInspector snapshot

                              else
                                Html.text ""
                            , if model.showModel then
                                viewModelInspector model.modelTreeExpanded previewSnapshot

                              else
                                Html.text ""
                            ]

            Nothing ->
                Html.div [ Attr.class "viewer-empty" ]
                    [ Html.text "No snapshots to display" ]
        ]


viewErrorPanel : String -> Html Msg
viewErrorPanel errorMsg =
    let
        ( title, details ) =
            case String.split " failed:\n\n" errorMsg of
                [ prefix, rest ] ->
                    ( prefix ++ " failed", rest )

                _ ->
                    case String.split ":\n\n" errorMsg of
                        [ prefix, rest ] ->
                            ( prefix, rest )

                        _ ->
                            ( "Test Failed", errorMsg )
    in
    Html.div [ Attr.class "error-panel" ]
        [ Html.div [ Attr.class "error-panel-header" ]
            [ Html.span [ Attr.class "error-panel-icon" ] [ Html.text "!" ]
            , Html.text title
            ]
        , Html.pre [ Attr.class "error-panel-body" ]
            [ Html.text details ]
        ]


viewUrlBar : Snapshot -> Html Msg
viewUrlBar snapshot =
    Html.div [ Attr.class "url-bar" ]
        [ Html.span [ Attr.class "url-bar-icon" ] [ Html.text ">" ]
        , Html.span [ Attr.class "url-bar-text" ]
            [ Html.text
                (snapshot.browserUrl
                    |> Maybe.withDefault "(no URL tracking)"
                )
            ]
        ]


viewRenderedPage : Snapshot -> Html Msg
viewRenderedPage snapshot =
    viewRenderedPageWithOptions Nothing Nothing snapshot


viewEmptyRenderedPage : Html Msg
viewEmptyRenderedPage =
    Html.div [ Attr.class "rendered-page" ]
        [ Html.node "iframe"
            [ Attr.id "preview-iframe"
            , Attr.attribute "src" "/_tests-preview"
            ]
            []
        ]


viewRenderedPageWithWidth : Maybe Int -> Snapshot -> Html Msg
viewRenderedPageWithWidth viewportWidth snapshot =
    viewRenderedPageWithOptions viewportWidth Nothing snapshot


viewRenderedPageWithOptions : Maybe Int -> Maybe PreviewMode -> Snapshot -> Html Msg
viewRenderedPageWithOptions viewportWidth maybePreviewMode snapshot =
    Html.div
        ([ Attr.classList
            [ ( "rendered-page", True )
            , ( "rendered-page-before", maybePreviewMode == Just Before )
            , ( "rendered-page-after", maybePreviewMode == Just After )
            ]
         ]
        )
        [ Html.div [ Attr.class "page-title-bar" ]
            [ Html.span [ Attr.class "page-title-dots" ]
                [ Html.span [ Attr.class "dot dot-red" ] []
                , Html.span [ Attr.class "dot dot-yellow" ] []
                , Html.span [ Attr.class "dot dot-green" ] []
                ]
            , Html.text snapshot.title
            , case maybePreviewMode of
                Just Before ->
                    Html.span [ Attr.class "preview-mode-badge preview-mode-before" ] [ Html.text "BEFORE" ]

                Just After ->
                    Html.span [ Attr.class "preview-mode-badge preview-mode-after" ] [ Html.text "AFTER" ]

                Nothing ->
                    Html.text ""
            ]
        , Html.div
            (Attr.class "page-body"
                :: (case ( snapshot.targetElement, snapshot.assertionSelectors ) of
                        ( Just (BySelectors sels), _ ) ->
                            [ Attr.attribute "data-highlight" (Encode.encode 0 (encodeInteractionHighlight sels snapshot.scopeSelectors)) ]

                        ( Just target, _ ) ->
                            [ Attr.attribute "data-highlight" (Encode.encode 0 (encodeTargetSelector target)) ]

                        ( Nothing, _ :: _ ) ->
                            [ Attr.attribute "data-highlight" (Encode.encode 0 (encodeAssertionHighlight snapshot.assertionSelectors snapshot.scopeSelectors)) ]

                        _ ->
                            []
                   )
            )
            (snapshot.body
                |> List.map (Html.map (\_ -> NoOp))
            )
        , Html.node "iframe"
            ([ Attr.id "preview-iframe"
             , Attr.attribute "src" "/_tests-preview"
             ]
                ++ (case viewportWidth of
                        Just w ->
                            [ Attr.style "width" (String.fromInt w ++ "px")
                            , Attr.style "margin-left" "auto"
                            , Attr.style "margin-right" "auto"
                            ]

                        Nothing ->
                            []
                   )
            )
            []
        ]


viewBeforeAfterToggle : PreviewMode -> Html Msg
viewBeforeAfterToggle current =
    Html.div [ Attr.class "before-after-toggle" ]
        [ Html.button
            [ Attr.classList
                [ ( "ba-btn", True )
                , ( "ba-btn-active", current == Before )
                ]
            , Html.Events.onClick (SetPreviewMode Before)
            ]
            [ Html.text "Before" ]
        , Html.button
            [ Attr.classList
                [ ( "ba-btn", True )
                , ( "ba-btn-active", current == After )
                ]
            , Html.Events.onClick (SetPreviewMode After)
            ]
            [ Html.text "After" ]
        ]


viewModelInspector : Set String -> Snapshot -> Html Msg
viewModelInspector expandedNodes snapshot =
    Html.div [ Attr.class "model-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ] [ Html.text "Model" ]
        , Html.div [ Attr.class "inspector-body" ]
            [ case snapshot.modelState of
                Nothing ->
                    Html.span [ Attr.class "dv-internals" ]
                        [ Html.text "(use withModelInspector to enable)" ]

                Just modelStr ->
                    case DebugParser.parse modelStr of
                        Ok value ->
                            DebugParser.viewValue
                                { expanded = expandedNodes
                                , onToggle = ToggleModelNode
                                }
                                "root"
                                value

                        Err _ ->
                            Html.pre [] [ Html.text modelStr ]
            ]
        ]


{-| Step-chip vocabulary shared between the Cookie, Network, and Fetcher panels.
-}
type ChipKind
    = ChipNow
    | ChipStart
    | ChipEnd
    | ChipChange
    | ChipError
    | ChipPast
    | ChipFuture


chipClass : ChipKind -> String
chipClass kind =
    case kind of
        ChipNow ->
            "step-chip step-chip-now"

        ChipStart ->
            "step-chip step-chip-start"

        ChipEnd ->
            "step-chip step-chip-end"

        ChipChange ->
            "step-chip step-chip-change"

        ChipError ->
            "step-chip step-chip-error"

        ChipPast ->
            "step-chip step-chip-past"

        ChipFuture ->
            "step-chip step-chip-future"


viewStepChip : { step : Int, kind : ChipKind, label : Maybe String } -> Html Msg
viewStepChip { step, kind, label } =
    Html.button
        [ Attr.class (chipClass kind)
        , Html.Events.onClick (GoToStep step)
        ]
        [ Html.span [ Attr.class "step-chip-num" ] [ Html.text (String.fromInt (step + 1)) ]
        , case label of
            Just text ->
                Html.span [ Attr.class "step-chip-label" ] [ Html.text text ]

            Nothing ->
                Html.text ""
        ]


viewChipTimeline : List { step : Int, kind : ChipKind, label : Maybe String } -> Html Msg
viewChipTimeline items =
    Html.span [ Attr.class "step-chip-timeline" ]
        (items
            |> List.indexedMap
                (\i it ->
                    if i == 0 then
                        viewStepChip it

                    else
                        Html.span [ Attr.class "step-chip-group" ]
                            [ Html.span [ Attr.class "step-chip-arrow" ] [ Html.text "→" ]
                            , viewStepChip it
                            ]
                )
        )


viewFetcherInspector : Int -> List Snapshot -> Html Msg
viewFetcherInspector currentStep allSnapshots =
    let
        allFetcherIds =
            allSnapshots
                |> List.concatMap (.fetcherLog >> List.map .id)
                |> List.foldl
                    (\id acc ->
                        if List.member id acc then
                            acc

                        else
                            acc ++ [ id ]
                    )
                    []

        fetcherTimeline : String -> List ( Int, FetcherEntry )
        fetcherTimeline fetcherId =
            allSnapshots
                |> List.indexedMap
                    (\i snap ->
                        snap.fetcherLog
                            |> List.filter (\f -> f.id == fetcherId)
                            |> List.head
                            |> Maybe.map (\entry -> ( i, entry ))
                    )
                |> List.filterMap identity
                |> dedupeFetcherTimeline

        activeEntry : String -> Maybe ( Int, FetcherEntry )
        activeEntry fetcherId =
            fetcherTimeline fetcherId
                |> List.filter (\( idx, _ ) -> idx <= currentStep)
                |> List.reverse
                |> List.head

        isLiveFetcher fetcherId =
            case activeEntry fetcherId of
                Just ( _, entry ) ->
                    entry.status == FetcherSubmitting || entry.status == FetcherReloading

                Nothing ->
                    False

        liveCount =
            allFetcherIds |> List.filter isLiveFetcher |> List.length

        statusChipKind : Int -> FetcherStatus -> ChipKind
        statusChipKind stepIdx status =
            if stepIdx > currentStep then
                ChipFuture

            else
                case status of
                    FetcherSubmitting ->
                        ChipStart

                    FetcherReloading ->
                        ChipChange

                    FetcherComplete ->
                        ChipEnd

        statusWord status =
            case status of
                FetcherSubmitting ->
                    "submit"

                FetcherReloading ->
                    "reload"

                FetcherComplete ->
                    "done"

        viewFetcherCard fetcherId =
            let
                timeline =
                    fetcherTimeline fetcherId

                firstEntry =
                    timeline |> List.head |> Maybe.map Tuple.second

                currentEntry =
                    activeEntry fetcherId

                isLive =
                    isLiveFetcher fetcherId

                submitEntry : Maybe ( Int, FetcherEntry )
                submitEntry =
                    timeline
                        |> List.filter (\( _, e ) -> e.status == FetcherSubmitting)
                        |> List.head

                submitFields : List ( String, String )
                submitFields =
                    submitEntry
                        |> Maybe.map (Tuple.second >> .fields)
                        |> Maybe.withDefault []

                resolveEntries : List ( Int, FetcherEntry )
                resolveEntries =
                    timeline
                        |> List.filter (\( _, e ) -> e.status /= FetcherSubmitting)

                overallBadge : Html Msg
                overallBadge =
                    if isLive then
                        Html.span [ Attr.class "fetcher-live-badge" ]
                            [ Html.text "● LIVE" ]

                    else
                        case currentEntry of
                            Just ( _, entry ) ->
                                case entry.status of
                                    FetcherComplete ->
                                        Html.span
                                            [ Attr.class "fetcher-done-badge" ]
                                            [ Html.text "✓ done" ]

                                    _ ->
                                        Html.span [ Attr.class "fetcher-state-label" ]
                                            [ Html.text (statusWord entry.status) ]

                            Nothing ->
                                Html.text ""

                submitLaneBody : Html Msg
                submitLaneBody =
                    case submitEntry of
                        Just ( stepIdx, _ ) ->
                            Html.div [ Attr.class "fetcher-lane-body" ]
                                [ viewStepChip
                                    { step = stepIdx
                                    , kind = statusChipKind stepIdx FetcherSubmitting
                                    , label = Just "step"
                                    }
                                , if List.isEmpty submitFields then
                                    Html.text ""

                                  else
                                    Html.span [ Attr.class "fetcher-fields" ]
                                        [ Html.text "optimistic: "
                                        , Html.span [ Attr.class "fetcher-fields-payload" ]
                                            [ Html.text
                                                (submitFields
                                                    |> List.map (\( k, v ) -> k ++ "=" ++ v)
                                                    |> String.join ", "
                                                )
                                            ]
                                        ]
                                ]

                        Nothing ->
                            Html.div [ Attr.class "fetcher-lane-body fetcher-lane-empty" ]
                                [ Html.text "—" ]

                resolveLaneBody : Html Msg
                resolveLaneBody =
                    if List.isEmpty resolveEntries then
                        Html.div [ Attr.class "fetcher-lane-body fetcher-lane-empty" ]
                            [ Html.text "pending…" ]

                    else
                        Html.div [ Attr.class "fetcher-lane-body" ]
                            [ viewChipTimeline
                                (resolveEntries
                                    |> List.map
                                        (\( stepIdx, entry ) ->
                                            { step = stepIdx
                                            , kind = statusChipKind stepIdx entry.status
                                            , label = Just (statusWord entry.status)
                                            }
                                        )
                                )
                            ]
            in
            Html.div
                [ Attr.classList
                    [ ( "fetcher-card", True )
                    , ( "fetcher-card-live", isLive )
                    ]
                ]
                [ Html.div [ Attr.class "fetcher-card-header" ]
                    [ case firstEntry of
                        Just entry ->
                            Html.span [ Attr.class "net-method net-method-http" ]
                                [ Html.text entry.method ]

                        Nothing ->
                            Html.text ""
                    , Html.span [ Attr.class "fetcher-id" ] [ Html.text ("\"" ++ fetcherId ++ "\"") ]
                    , Html.span [ Attr.class "fetcher-spacer" ] []
                    , overallBadge
                    ]
                , Html.div [ Attr.class "fetcher-lanes" ]
                    [ Html.div [ Attr.class "fetcher-lane fetcher-lane-submit" ]
                        [ Html.span [ Attr.class "fetcher-lane-label" ]
                            [ Html.text "SUBMIT ↑" ]
                        , submitLaneBody
                        ]
                    , Html.div [ Attr.class "fetcher-lane fetcher-lane-resolve" ]
                        [ Html.span [ Attr.class "fetcher-lane-label" ]
                            [ Html.text "RESOLVE ↓" ]
                        , resolveLaneBody
                        ]
                    ]
                ]
    in
    Html.div [ Attr.class "fetcher-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ]
            [ Html.span [ Attr.class "sidebar-title" ]
                [ Html.text "Fetchers" ]
            , Html.span [ Attr.class "sidebar-subtitle" ]
                [ Html.text (String.fromInt (List.length allFetcherIds) ++ " · step " ++ String.fromInt (currentStep + 1))
                , if liveCount > 0 then
                    Html.span [ Attr.class "fetcher-live-count" ]
                        [ Html.text (" · " ++ String.fromInt liveCount ++ " live") ]

                  else
                    Html.text ""
                ]
            ]
        , if List.isEmpty allFetcherIds then
            Html.div [ Attr.class "fetcher-empty" ]
                [ Html.text "No fetcher submissions in this test." ]

          else
            Html.div [ Attr.class "fetcher-list" ]
                (allFetcherIds |> List.map viewFetcherCard)
        ]


dedupeFetcherTimeline : List ( Int, FetcherEntry ) -> List ( Int, FetcherEntry )
dedupeFetcherTimeline entries =
    entries
        |> List.foldl
            (\( i, entry ) acc ->
                case acc of
                    ( _, prev ) :: _ ->
                        if prev.status == entry.status then
                            acc

                        else
                            ( i, entry ) :: acc

                    [] ->
                        [ ( i, entry ) ]
            )
            []
        |> List.reverse


viewEffectInspector : Snapshot -> Html Msg
viewEffectInspector snapshot =
    Html.div [ Attr.class "effect-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ]
            [ Html.text
                ("Effects ("
                    ++ String.fromInt (List.length snapshot.pendingEffects)
                    ++ ")"
                )
            ]
        , if List.isEmpty snapshot.pendingEffects then
            Html.div [ Attr.class "effect-empty" ]
                [ Html.text "No pending effects at this step." ]

          else
            Html.div [ Attr.class "effect-list" ]
                (snapshot.pendingEffects
                    |> List.map
                        (\desc ->
                            let
                                ( method, url ) =
                                    case String.split " " desc of
                                        m :: rest ->
                                            ( m, String.join " " rest )

                                        _ ->
                                            ( "", desc )

                                isHttp =
                                    List.member method [ "GET", "POST", "PUT", "DELETE", "PATCH" ]
                            in
                            Html.div [ Attr.class "effect-item" ]
                                [ if isHttp then
                                    Html.span []
                                        [ Html.span [ Attr.class "effect-method" ] [ Html.text method ]
                                        , Html.span [ Attr.class "effect-url" ] [ Html.text (" " ++ url) ]
                                        ]

                                  else
                                    Html.span [ Attr.class "effect-desc" ] [ Html.text desc ]
                                ]
                        )
                )
        ]



{-| Network entry with its life-span across the snapshot stream: the step at
which it was first observed, and (if any) the step at which its status became
`Stubbed`. `endStep == Nothing` at the current step means the request is still
in flight.
-}
type alias NetworkLane =
    { entry : NetworkEntry
    , startStep : Int
    , endStep : Maybe Int
    }


{-| Compute the end step for each unique network entry by walking the cumulative
snapshot logs. The *first* snapshot in which the entry's status becomes
`Stubbed` is its end step.
-}
buildNetworkLanes : List Snapshot -> List NetworkLane
buildNetworkLanes allSnapshots =
    let
        laneKey entry =
            entry.url ++ ":" ++ String.fromInt entry.stepIndex

        endStepOf : NetworkEntry -> Maybe Int
        endStepOf entry =
            allSnapshots
                |> List.indexedMap Tuple.pair
                |> List.filterMap
                    (\( i, snap ) ->
                        snap.networkLog
                            |> List.filter
                                (\e ->
                                    e.url == entry.url
                                        && e.stepIndex == entry.stepIndex
                                        && e.status
                                        == Stubbed
                                )
                            |> List.head
                            |> Maybe.map (\_ -> i)
                    )
                |> List.head
    in
    allSnapshots
        |> List.concatMap .networkLog
        |> List.foldl
            (\entry ( seenKeys, acc ) ->
                let
                    key =
                        laneKey entry
                in
                if List.member key seenKeys then
                    ( seenKeys, acc )

                else
                    ( key :: seenKeys
                    , { entry = entry, startStep = entry.stepIndex, endStep = endStepOf entry } :: acc
                    )
            )
            ( [], [] )
        |> Tuple.second
        |> List.reverse


type LaneState
    = LaneFuture
    | LaneInFlight
    | LaneResolving
    | LaneResolved


laneStateAt : Int -> NetworkLane -> LaneState
laneStateAt step lane =
    if step < lane.startStep then
        LaneFuture

    else
        case lane.endStep of
            Nothing ->
                LaneInFlight

            Just end ->
                if step < end then
                    LaneInFlight

                else if step == end then
                    LaneResolving

                else
                    LaneResolved


viewNetworkSidebar : Model -> Int -> List Snapshot -> Html Msg
viewNetworkSidebar model currentStep allSnapshots =
    let
        allLanes =
            buildNetworkLanes allSnapshots

        hasBackend =
            List.any (\l -> l.entry.source == Backend) allLanes

        hasFrontend =
            List.any (\l -> l.entry.source == Frontend) allLanes

        visibleLanes =
            allLanes
                |> List.filter
                    (\l ->
                        case l.entry.source of
                            Backend ->
                                model.showNetworkBackend

                            Frontend ->
                                model.showNetworkFrontend
                    )

        liveCount =
            visibleLanes
                |> List.filter
                    (\l ->
                        case laneStateAt currentStep l of
                            LaneInFlight ->
                                True

                            LaneResolving ->
                                True

                            _ ->
                                False
                    )
                |> List.length
    in
    Html.div [ Attr.class "network-sidebar" ]
        [ Html.div [ Attr.class "network-sidebar-header" ]
            [ Html.div [ Attr.class "network-sidebar-title-row" ]
                [ Html.span [ Attr.class "sidebar-title" ]
                    [ Html.text "Network" ]
                , Html.span [ Attr.class "sidebar-subtitle" ]
                    [ Html.text (String.fromInt (List.length visibleLanes))
                    , if liveCount > 0 then
                        Html.span [ Attr.class "net-live-count" ]
                            [ Html.text (" · " ++ String.fromInt liveCount ++ " live") ]

                      else
                        Html.text ""
                    ]
                ]
            , if hasBackend || hasFrontend then
                Html.div [ Attr.class "net-filter-buttons" ]
                    [ Html.button
                        [ Attr.classList
                            [ ( "net-filter-btn net-filter-backend", True )
                            , ( "net-filter-active", model.showNetworkBackend )
                            ]
                        , Html.Events.onClick ToggleNetworkBackend
                        ]
                        [ Html.text "Backend" ]
                    , Html.button
                        [ Attr.classList
                            [ ( "net-filter-btn net-filter-frontend", True )
                            , ( "net-filter-active", model.showNetworkFrontend )
                            ]
                        , Html.Events.onClick ToggleNetworkFrontend
                        ]
                        [ Html.text "Frontend" ]
                    ]

              else
                Html.text ""
            ]
        , if List.isEmpty visibleLanes then
            Html.div [ Attr.class "network-empty" ]
                [ Html.text
                    (if List.isEmpty allLanes then
                        "No HTTP requests recorded."

                     else
                        "No matching requests. Adjust filters above."
                    )
                ]

          else
            Html.div [ Attr.class "network-list" ]
                (List.map (\l -> viewNetworkRow currentStep l) visibleLanes)
        ]


viewNetworkRow : Int -> NetworkLane -> Html Msg
viewNetworkRow currentStep lane =
    let
        state =
            laneStateAt currentStep lane

        stateClass =
            case state of
                LaneFuture ->
                    "net-row-future"

                LaneInFlight ->
                    "net-row-inflight"

                LaneResolving ->
                    "net-row-resolving"

                LaneResolved ->
                    "net-row-resolved"

        isPort =
            lane.entry.portName /= Nothing

        methodClass =
            if isPort then
                "net-method-port"

            else
                "net-method-http"

        pathLabel =
            case lane.entry.portName of
                Just name ->
                    name

                Nothing ->
                    lane.entry.url

        hasDetails =
            not (List.isEmpty lane.entry.requestHeaders)
                || lane.entry.requestBody
                /= Nothing
                || lane.entry.responsePreview
                /= Nothing

        summaryContent =
            [ Html.div [ Attr.class "net-row-head" ]
                [ viewNetStateBadge state
                , Html.span [ Attr.class ("net-method " ++ methodClass) ]
                    [ Html.text lane.entry.method ]
                , Html.span [ Attr.class "net-row-path", Attr.title lane.entry.url ]
                    [ Html.text pathLabel ]
                ]
            , Html.div [ Attr.class "net-row-chips" ]
                (viewStepChip { step = lane.startStep, kind = ChipStart, label = Just "start" }
                    :: (case lane.endStep of
                            Just end ->
                                [ Html.span [ Attr.class "step-chip-arrow" ] [ Html.text "→" ]
                                , viewStepChip { step = end, kind = ChipEnd, label = Just "end" }
                                ]

                            Nothing ->
                                [ Html.span [ Attr.class "step-chip-arrow net-row-chip-arrow-live" ] [ Html.text "→" ]
                                , Html.span [ Attr.class "net-row-inflight-text" ] [ Html.text "in flight…" ]
                                ]
                       )
                    ++ [ case state of
                            LaneInFlight ->
                                Html.span [ Attr.class "net-row-live-badge" ]
                                    [ Html.text "● LIVE" ]

                            _ ->
                                Html.text ""
                       ]
                )
            ]
    in
    if hasDetails then
        Html.details
            [ Attr.classList
                [ ( "net-row", True )
                , ( stateClass, True )
                ]
            ]
            (Html.summary [ Attr.class "net-row-summary" ] summaryContent
                :: [ viewNetRowDetails lane.entry ]
            )

    else
        Html.div
            [ Attr.classList
                [ ( "net-row", True )
                , ( stateClass, True )
                ]
            ]
            summaryContent


viewNetStateBadge : LaneState -> Html Msg
viewNetStateBadge state =
    let
        ( cls, label, icon ) =
            case state of
                LaneFuture ->
                    ( "net-state-future", "future", "○" )

                LaneInFlight ->
                    ( "net-state-inflight", "in flight", "●" )

                LaneResolving ->
                    ( "net-state-resolving", "resolved", "✓" )

                LaneResolved ->
                    ( "net-state-past", "past", "✓" )
    in
    Html.span [ Attr.class ("net-state-badge " ++ cls) ]
        [ Html.span [ Attr.class "net-state-icon" ] [ Html.text icon ]
        , Html.text label
        ]


viewNetRowDetails : NetworkEntry -> Html Msg
viewNetRowDetails entry =
    Html.div [ Attr.class "net-row-details" ]
        (List.filterMap identity
            [ if List.isEmpty entry.requestHeaders then
                Nothing

              else
                Just
                    (Html.details [ Attr.class "net-response-details" ]
                        [ Html.summary [ Attr.class "net-response-summary net-headers-summary" ]
                            [ Html.text ("Headers (" ++ String.fromInt (List.length entry.requestHeaders) ++ ")") ]
                        , Html.div [ Attr.class "net-headers-list" ]
                            (entry.requestHeaders
                                |> List.map
                                    (\( name, value ) ->
                                        Html.div [ Attr.class "net-header-row" ]
                                            [ Html.span [ Attr.class "net-header-name" ] [ Html.text (name ++ ": ") ]
                                            , Html.span [ Attr.class "net-header-value" ] [ Html.text value ]
                                            ]
                                    )
                            )
                        ]
                    )
            , entry.requestBody
                |> Maybe.map
                    (\body ->
                        Html.details [ Attr.class "net-response-details" ]
                            [ Html.summary [ Attr.class "net-response-summary net-request-summary" ]
                                [ Html.text "Request Body" ]
                            , Html.pre [ Attr.class "net-response-body" ]
                                [ Html.text (formatJsonPreview body) ]
                            ]
                    )
            , entry.responsePreview
                |> Maybe.map
                    (\preview ->
                        Html.details [ Attr.class "net-response-details" ]
                            [ Html.summary [ Attr.class "net-response-summary" ]
                                [ Html.text "Response" ]
                            , Html.pre [ Attr.class "net-response-body" ]
                                [ Html.text (formatJsonPreview preview) ]
                            ]
                    )
            ]
        )


{-| A change event in a cookie's history — one stack-card in Variant B.
`CookieSet` is the first appearance; `CookieUpdated` is a distinct later value;
`CookieRemoved` is the step where the cookie disappears from the jar.
-}
type CookieEvent
    = CookieSet CookieEntry
    | CookieUpdated CookieEntry
    | CookieRemoved


cookieEventEntry : CookieEvent -> Maybe CookieEntry
cookieEventEntry ev =
    case ev of
        CookieSet e ->
            Just e

        CookieUpdated e ->
            Just e

        CookieRemoved ->
            Nothing


viewCookieSidebar : Int -> List Snapshot -> Html Msg
viewCookieSidebar currentStep allSnapshots =
    let
        allNames : List String
        allNames =
            allSnapshots
                |> List.concatMap (.cookieLog >> List.map Tuple.first)
                |> List.foldl
                    (\n acc ->
                        if List.member n acc then
                            acc

                        else
                            acc ++ [ n ]
                    )
                    []

        cookieEvents : String -> List ( Int, CookieEvent )
        cookieEvents name =
            buildCookieEvents name allSnapshots

        totalSteps =
            List.length allSnapshots

        isChangingCookie : String -> Bool
        isChangingCookie name =
            let
                events =
                    cookieEvents name

                signed =
                    activeCookieEvent currentStep events
                        |> Maybe.andThen (Tuple.second >> cookieEventEntry)
                        |> Maybe.map .value
                        |> Maybe.andThen BackendTaskTest.mockUnsignValue
                        |> (/=) Nothing
            in
            List.length events > 1 || signed

        changing =
            allNames |> List.filter isChangingCookie

        noChange =
            allNames |> List.filter (\n -> not (isChangingCookie n))
    in
    Html.div [ Attr.class "cookie-sidebar" ]
        [ Html.div [ Attr.class "cookie-sidebar-header" ]
            [ Html.span [ Attr.class "sidebar-title" ]
                [ Html.text "Cookies" ]
            , Html.span [ Attr.class "sidebar-subtitle" ]
                [ Html.text "diff · box pills" ]
            ]
        , if List.isEmpty allNames then
            Html.div [ Attr.class "cookie-empty" ]
                [ Html.text "No cookies set by this test." ]

          else
            Html.div [ Attr.class "cookie-list" ]
                ((changing
                    |> List.map
                        (\name ->
                            viewCookieStack currentStep totalSteps name (cookieEvents name)
                        )
                 )
                    ++ (if List.isEmpty noChange then
                            []

                        else
                            [ Html.div [ Attr.class "cookie-nochange-section" ]
                                (Html.div [ Attr.class "cookie-nochange-header" ]
                                    [ Html.text "— no-change cookies —" ]
                                    :: (noChange
                                            |> List.map
                                                (\name ->
                                                    viewNoChangeCookie currentStep name (cookieEvents name)
                                                )
                                       )
                                )
                            ]
                       )
                )
        ]


viewNoChangeCookie : Int -> String -> List ( Int, CookieEvent ) -> Html Msg
viewNoChangeCookie currentStep name events =
    let
        activeEntry =
            activeCookieEvent currentStep events
                |> Maybe.andThen (Tuple.second >> cookieEventEntry)

        valueText =
            case activeEntry of
                Just e ->
                    e.value

                Nothing ->
                    "—"
    in
    Html.div [ Attr.class "cookie-nochange-row" ]
        [ Html.span [ Attr.class "cookie-name" ] [ Html.text name ]
        , Html.span [ Attr.class "cookie-nochange-sep" ] [ Html.text "·" ]
        , Html.span [ Attr.class "cookie-nochange-value" ] [ Html.text valueText ]
        ]


{-| Walk the snapshot stream and turn it into a list of change events for one
cookie. Consecutive snapshots with identical entries collapse; removal is
detected when the cookie disappears from the jar after having been present.
-}
buildCookieEvents : String -> List Snapshot -> List ( Int, CookieEvent )
buildCookieEvents name allSnapshots =
    let
        lookup snap =
            snap.cookieLog
                |> List.filter (\( n, _ ) -> n == name)
                |> List.head
                |> Maybe.map Tuple.second

        step :
            ( Int, Snapshot )
            -> { prev : Maybe CookieEntry, acc : List ( Int, CookieEvent ) }
            -> { prev : Maybe CookieEntry, acc : List ( Int, CookieEvent ) }
        step ( i, snap ) state =
            case ( state.prev, lookup snap ) of
                ( Nothing, Just entry ) ->
                    { prev = Just entry, acc = ( i, CookieSet entry ) :: state.acc }

                ( Just prevEntry, Just entry ) ->
                    if prevEntry == entry then
                        { state | prev = Just entry }

                    else
                        { prev = Just entry, acc = ( i, CookieUpdated entry ) :: state.acc }

                ( Just _, Nothing ) ->
                    { prev = Nothing, acc = ( i, CookieRemoved ) :: state.acc }

                ( Nothing, Nothing ) ->
                    state

        final =
            allSnapshots
                |> List.indexedMap Tuple.pair
                |> List.foldl step { prev = Nothing, acc = [] }
    in
    List.reverse final.acc


hasActiveCookieAt : Int -> List ( Int, CookieEvent ) -> Bool
hasActiveCookieAt step events =
    case activeCookieEvent step events of
        Just ( _, CookieSet _ ) ->
            True

        Just ( _, CookieUpdated _ ) ->
            True

        _ ->
            False


activeCookieEvent : Int -> List ( Int, CookieEvent ) -> Maybe ( Int, CookieEvent )
activeCookieEvent step events =
    events
        |> List.filter (\( i, _ ) -> i <= step)
        |> List.reverse
        |> List.head


viewCookieStack : Int -> Int -> String -> List ( Int, CookieEvent ) -> Html Msg
viewCookieStack currentStep totalSteps name events =
    let
        currentEventIdx : Maybe Int
        currentEventIdx =
            events
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, ( step, _ ) ) -> step <= currentStep)
                |> List.reverse
                |> List.head
                |> Maybe.map Tuple.first

        activeEvent : Maybe ( Int, CookieEvent )
        activeEvent =
            activeCookieEvent currentStep events

        previousEventTuple : Maybe ( Int, CookieEvent )
        previousEventTuple =
            case currentEventIdx of
                Just idx ->
                    if idx > 0 then
                        events |> List.drop (idx - 1) |> List.head

                    else
                        Nothing

                Nothing ->
                    Nothing

        previousEventEntry : Maybe CookieEntry
        previousEventEntry =
            previousEventTuple |> Maybe.andThen (Tuple.second >> cookieEventEntry)

        previousEventStep : Maybe Int
        previousEventStep =
            previousEventTuple |> Maybe.map Tuple.first

        signed : Maybe { secret : String, values : Encode.Value }
        signed =
            activeEvent
                |> Maybe.andThen (Tuple.second >> cookieEventEntry)
                |> Maybe.map .value
                |> Maybe.andThen BackendTaskTest.mockUnsignValue

        previousSigned : Maybe Encode.Value
        previousSigned =
            previousEventEntry
                |> Maybe.map .value
                |> Maybe.andThen BackendTaskTest.mockUnsignValue
                |> Maybe.map .values

        activeEntry =
            activeEvent |> Maybe.andThen (Tuple.second >> cookieEventEntry)

        eventCount =
            List.length events

        hasCurrent =
            currentEventIdx /= Nothing

        isRemovedNow =
            case activeEvent of
                Just ( _, CookieRemoved ) ->
                    True

                _ ->
                    False

        -- Only show the SET/CHANGED/REMOVED pill in the header when the active
        -- event's step is literally the current step — this tells the reader
        -- "something happened to this cookie right now".
        headerEventPill : Html Msg
        headerEventPill =
            case activeEvent of
                Just ( evStep, ev ) ->
                    if evStep == currentStep then
                        viewCookieEventBadge ev

                    else
                        Html.text ""

                Nothing ->
                    Html.text ""
    in
    Html.div [ Attr.class "cookie-stack" ]
        [ Html.div [ Attr.class "cookie-stack-header" ]
            [ Html.span [ Attr.class "cookie-name" ] [ Html.text name ]
            , case signed of
                Just _ ->
                    Html.span [ Attr.class "cookie-signed-badge" ]
                        [ Html.text "signed" ]

                Nothing ->
                    Html.text ""
            , headerEventPill
            , Html.span [ Attr.class "cookie-stack-count" ]
                [ Html.text
                    (String.fromInt eventCount
                        ++ (if eventCount == 1 then
                                " value"

                            else
                                " values"
                           )
                    )
                ]
            ]
        , case signed of
            Just { secret } ->
                Html.div [ Attr.class "cookie-secret-label" ]
                    [ Html.text "signed with "
                    , Html.code [] [ Html.text ("\"" ++ secret ++ "\"") ]
                    , Html.span [ Attr.class "cookie-fnv-note" ]
                        [ Html.text "fnv1a (dev)" ]
                    ]

            Nothing ->
                Html.text ""
        , if eventCount > 1 then
            viewCookiePillRow currentStep currentEventIdx events

          else
            Html.text ""
        , case activeEvent of
            Just ( evStep, ev ) ->
                if evStep == currentStep then
                    viewCookieDiffCard
                        { currentStep = currentStep
                        , eventStep = evStep
                        , event = ev
                        , isFirstEvent = currentEventIdx == Just 0
                        , previousEventEntry = previousEventEntry
                        , previousEventStep = previousEventStep
                        , signed = signed
                        , previousSigned = previousSigned
                        }

                else
                    viewCookieCurrentCard
                        { eventStep = evStep
                        , event = ev
                        , signed = signed
                        }

            Nothing ->
                Html.div [ Attr.class "cookie-stack-empty" ] [ Html.text "not set yet" ]
        , if hasCurrent && not isRemovedNow then
            case activeEntry of
                Just entry ->
                    Html.details [ Attr.class "cookie-details" ]
                        [ Html.summary [ Attr.class "cookie-details-summary" ]
                            [ Html.text "Attributes + raw value" ]
                        , viewCookieAttrTable entry
                        , Html.pre [ Attr.class "cookie-raw-value" ]
                            [ Html.text entry.value ]
                        ]

                Nothing ->
                    Html.text ""

          else
            Html.text ""
        ]


viewCookieEventBadge : CookieEvent -> Html Msg
viewCookieEventBadge ev =
    let
        ( cls, label ) =
            case ev of
                CookieSet _ ->
                    ( "cookie-event-badge-set", "SET" )

                CookieUpdated _ ->
                    ( "cookie-event-badge-changed", "CHANGED" )

                CookieRemoved ->
                    ( "cookie-event-badge-removed", "REMOVED" )
    in
    Html.span
        [ Attr.classList
            [ ( "cookie-event-badge", True )
            , ( cls, True )
            ]
        ]
        [ Html.text label ]


{-| C3 "box-pills" step selector. One pill per value-change event; left border
colored by event kind (set = green, updated = yellow, removed = red). The pill
matching the current event is filled cyan; the pill whose step equals the
global step also shows a `·now` marker. Clicking a pill jumps the viewer to
that change point.
-}
viewCookiePillRow : Int -> Maybe Int -> List ( Int, CookieEvent ) -> Html Msg
viewCookiePillRow currentStep currentEventIdx events =
    Html.div [ Attr.class "cookie-pill-row" ]
        (events
            |> List.indexedMap
                (\idx ( evStep, ev ) ->
                    let
                        kindClass =
                            case ev of
                                CookieSet _ ->
                                    "cookie-pill-kind-set"

                                CookieUpdated _ ->
                                    "cookie-pill-kind-changed"

                                CookieRemoved ->
                                    "cookie-pill-kind-removed"

                        isActive =
                            currentEventIdx == Just idx

                        isNow =
                            evStep == currentStep
                    in
                    Html.button
                        [ Attr.classList
                            [ ( "cookie-box-pill", True )
                            , ( kindClass, True )
                            , ( "cookie-box-pill-active", isActive )
                            ]
                        , Html.Events.onClick (GoToStep evStep)
                        ]
                        [ Html.span [ Attr.class "cookie-box-pill-step" ]
                            [ Html.text (String.fromInt (evStep + 1)) ]
                        , if isNow then
                            Html.span [ Attr.class "cookie-box-pill-now" ]
                                [ Html.text "·now" ]

                          else
                            Html.text ""
                        ]
                )
        )


{-| A single panel that shows the current event as either `INITIAL · step N`
(first event, no previous to diff against) or `DIFF · prev → cur`. For signed
cookies the body is the PERSISTENT + FLASH sections with per-key +/-/→ rows.
For unsigned cookies the body is the raw value with a `+` / `-` prefix.
-}
viewCookieDiffCard :
    { currentStep : Int
    , eventStep : Int
    , event : CookieEvent
    , isFirstEvent : Bool
    , previousEventEntry : Maybe CookieEntry
    , previousEventStep : Maybe Int
    , signed : Maybe { secret : String, values : Encode.Value }
    , previousSigned : Maybe Encode.Value
    }
    -> Html Msg
viewCookieDiffCard cfg =
    let
        prevStepLabel =
            case cfg.previousEventStep of
                Just p ->
                    String.fromInt (p + 1)

                Nothing ->
                    "?"

        titleText =
            case cfg.event of
                CookieSet _ ->
                    if cfg.isFirstEvent then
                        "INITIAL · step " ++ String.fromInt (cfg.eventStep + 1)

                    else
                        "RE-SET · step " ++ String.fromInt (cfg.eventStep + 1)

                CookieUpdated _ ->
                    "DIFF · " ++ prevStepLabel ++ " → " ++ String.fromInt (cfg.eventStep + 1)

                CookieRemoved ->
                    "REMOVED · step " ++ String.fromInt (cfg.eventStep + 1)

        bodyRows : List (Html Msg)
        bodyRows =
            case ( cfg.signed, cfg.event ) of
                ( Just sig, CookieRemoved ) ->
                    viewDecodedPayloadRows cfg.currentStep (Just sig.values) Encode.null

                ( Just sig, _ ) ->
                    viewDecodedPayloadRows cfg.currentStep cfg.previousSigned sig.values

                ( Nothing, _ ) ->
                    viewRawDiffRows cfg.event cfg.previousEventEntry
    in
    Html.div [ Attr.class "cookie-diff-card" ]
        (Html.div [ Attr.class "cookie-diff-card-title" ] [ Html.text titleText ]
            :: bodyRows
        )


{-| Raw-value diff rendering for unsigned cookies.

* `CookieSet` → `+ value`
* `CookieUpdated` → `- prev` then `+ new`
* `CookieRemoved` → `- prev`

-}
viewRawDiffRows : CookieEvent -> Maybe CookieEntry -> List (Html Msg)
viewRawDiffRows event previousEntry =
    case event of
        CookieSet entry ->
            [ rawAddedRow entry.value ]

        CookieUpdated entry ->
            case previousEntry of
                Just prev ->
                    [ rawRemovedRow prev.value
                    , rawAddedRow entry.value
                    ]

                Nothing ->
                    [ rawAddedRow entry.value ]

        CookieRemoved ->
            case previousEntry of
                Just prev ->
                    [ rawRemovedRow prev.value ]

                Nothing ->
                    []


rawAddedRow : String -> Html Msg
rawAddedRow value =
    Html.div [ Attr.class "cookie-raw-row cookie-raw-row-added" ]
        [ Html.span [ Attr.class "cookie-raw-sign" ] [ Html.text "+" ]
        , Html.span [ Attr.class "cookie-raw-value-text" ] [ Html.text value ]
        ]


rawRemovedRow : String -> Html Msg
rawRemovedRow value =
    Html.div [ Attr.class "cookie-raw-row cookie-raw-row-removed" ]
        [ Html.span [ Attr.class "cookie-raw-sign" ] [ Html.text "−" ]
        , Html.span [ Attr.class "cookie-raw-value-text" ] [ Html.text value ]
        ]


rawCurrentRow : String -> Html Msg
rawCurrentRow value =
    Html.div [ Attr.class "cookie-raw-row cookie-raw-row-current" ]
        [ Html.span [ Attr.class "cookie-raw-sign" ] [ Html.text " " ]
        , Html.span [ Attr.class "cookie-raw-value-text" ] [ Html.text value ]
        ]


{-| The "held value" panel shown on steps where nothing changed at the
current step. Title tells the reader when the value was last written;
the body shows the current contents with no +/- markers so the reader
sees this as a state snapshot, not a diff.

For `CookieRemoved` events on non-change steps (i.e. the cookie has been
gone for a while) we render nothing — the box-pill row already tells the
story.

-}
viewCookieCurrentCard :
    { eventStep : Int
    , event : CookieEvent
    , signed : Maybe { secret : String, values : Encode.Value }
    }
    -> Html Msg
viewCookieCurrentCard cfg =
    case cfg.event of
        CookieRemoved ->
            Html.text ""

        _ ->
            let
                titleText =
                    "CURRENT · held since step " ++ String.fromInt (cfg.eventStep + 1)

                bodyRows =
                    case cfg.signed of
                        Just sig ->
                            viewDecodedPayloadStatic sig.values

                        Nothing ->
                            case cookieEventEntry cfg.event of
                                Just entry ->
                                    [ rawCurrentRow entry.value ]

                                Nothing ->
                                    []
            in
            Html.div [ Attr.class "cookie-diff-card cookie-current-card" ]
                (Html.div [ Attr.class "cookie-diff-card-title" ] [ Html.text titleText ]
                    :: bodyRows
                )


viewCookieAttrTable : CookieEntry -> Html Msg
viewCookieAttrTable entry =
    Html.div [ Attr.class "cookie-attr-table" ]
        [ attrRow "Path" (entry.path |> Maybe.withDefault unsetMarker)
        , attrRow "Domain" (entry.domain |> Maybe.withDefault unsetMarker)
        , attrRow "Expires" (entry.expires |> Maybe.withDefault unsetMarker)
        , attrRow "Max-Age" (entry.maxAge |> Maybe.map String.fromInt |> Maybe.withDefault unsetMarker)
        , attrRow "Secure" (boolMarker entry.secure)
        , attrRow "HttpOnly" (boolMarker entry.httpOnly)
        , attrRow "SameSite" (entry.sameSite |> Maybe.withDefault unsetMarker)
        ]


unsetMarker : String
unsetMarker =
    "—"


boolMarker : Bool -> String
boolMarker b =
    if b then
        "true"

    else
        "false"


attrRow : String -> String -> Html Msg
attrRow name value =
    Html.div [ Attr.class "cookie-attr-row" ]
        [ Html.span [ Attr.class "cookie-attr-name" ] [ Html.text name ]
        , Html.span
            [ Attr.classList
                [ ( "cookie-attr-value", True )
                , ( "cookie-attr-unset", value == unsetMarker )
                ]
            ]
            [ Html.text value ]
        ]


type KeyDiff
    = KeyNew
    | KeyChanged String
    | KeyUnchanged
    | KeyRemoved String


decodeStringPairs : Encode.Value -> List ( String, String )
decodeStringPairs v =
    Decode.decodeValue (Decode.keyValuePairs Decode.string) v
        |> Result.withDefault []


{-| Diff the persistent key/value pairs of a decoded session payload against
the previous step's payload. Keys present only in `current` show up with
`KeyNew`, keys present only in `previous` become `KeyRemoved` rows appended
at the end (so the reader sees that the app removed them this step), and
keys that changed carry the previous value in `KeyChanged`.
-}
diffPairs : List ( String, String ) -> List ( String, String ) -> List ( String, String, KeyDiff )
diffPairs previous current =
    let
        prevDict : Dict String String
        prevDict =
            Dict.fromList previous

        currDict : Dict String String
        currDict =
            Dict.fromList current

        currentRows : List ( String, String, KeyDiff )
        currentRows =
            current
                |> List.map
                    (\( k, v ) ->
                        case Dict.get k prevDict of
                            Nothing ->
                                ( k, v, KeyNew )

                            Just prevV ->
                                if prevV == v then
                                    ( k, v, KeyUnchanged )

                                else
                                    ( k, v, KeyChanged prevV )
                    )

        removedRows : List ( String, String, KeyDiff )
        removedRows =
            previous
                |> List.filter (\( k, _ ) -> Dict.get k currDict == Nothing)
                |> List.map (\( k, v ) -> ( k, v, KeyRemoved v ))
    in
    currentRows ++ removedRows


{-| Decode a signed cookie's JSON payload into `PERSISTENT` and `FLASH`
sections, each rendered as a +/-/change diff against the previous payload.
Returns the list of section nodes (no outer wrapper) so the caller can embed
them in a diff card.

`CookieRemoved` events come in as `values = Encode.null`, producing a full
"removed everything" diff.
-}
viewDecodedPayloadRows : Int -> Maybe Encode.Value -> Encode.Value -> List (Html Msg)
viewDecodedPayloadRows currentStep previousValues values =
    let
        decodePairs v =
            Decode.decodeValue (Decode.keyValuePairs Decode.string) v
                |> Result.withDefault []

        currentPairs : List ( String, String )
        currentPairs =
            decodePairs values

        previousPairs : List ( String, String )
        previousPairs =
            previousValues
                |> Maybe.map decodeStringPairs
                |> Maybe.withDefault []

        ( currentFlash, currentPersistent ) =
            List.partition (\( k, _ ) -> String.startsWith BackendTaskTest.sessionFlashPrefix k) currentPairs

        ( prevFlash, prevPersistent ) =
            List.partition (\( k, _ ) -> String.startsWith BackendTaskTest.sessionFlashPrefix k) previousPairs

        stripFlash : List ( String, String ) -> List ( String, String )
        stripFlash =
            List.map
                (\( k, v ) ->
                    ( String.dropLeft (String.length BackendTaskTest.sessionFlashPrefix) k, v )
                )

        -- Step 0 is the baseline, so don't highlight anything as new/changed.
        diffEnabled =
            currentStep > 0

        persistentRows =
            if diffEnabled then
                diffPairs prevPersistent currentPersistent

            else
                currentPersistent |> List.map (\( k, v ) -> ( k, v, KeyNew ))

        flashRows =
            if diffEnabled then
                diffPairs (stripFlash prevFlash) (stripFlash currentFlash)

            else
                stripFlash currentFlash |> List.map (\( k, v ) -> ( k, v, KeyNew ))
    in
    [ viewPayloadSection "PERSISTENT" Nothing persistentRows
    , viewPayloadSection "FLASH" (Just "ONE-SHOT") flashRows
    ]


{-| Static (non-diff) rendering of a signed cookie's decoded payload. All rows
are `KeyUnchanged` so nothing shows a +/- sign or diff color — just the
current contents, split into PERSISTENT + FLASH sections.
-}
viewDecodedPayloadStatic : Encode.Value -> List (Html Msg)
viewDecodedPayloadStatic values =
    let
        pairs =
            Decode.decodeValue (Decode.keyValuePairs Decode.string) values
                |> Result.withDefault []

        ( flash, persistent ) =
            List.partition (\( k, _ ) -> String.startsWith BackendTaskTest.sessionFlashPrefix k) pairs

        flashStripped =
            flash
                |> List.map
                    (\( k, v ) ->
                        ( String.dropLeft (String.length BackendTaskTest.sessionFlashPrefix) k, v )
                    )

        asUnchanged =
            List.map (\( k, v ) -> ( k, v, KeyUnchanged ))
    in
    [ viewPayloadSection "PERSISTENT" Nothing (asUnchanged persistent)
    , viewPayloadSection "FLASH" (Just "ONE-SHOT") (asUnchanged flashStripped)
    ]


{-| Render one named section of a decoded signed-cookie payload. Hidden when
the row list is empty so we don't stamp an empty header.
-}
viewPayloadSection : String -> Maybe String -> List ( String, String, KeyDiff ) -> Html Msg
viewPayloadSection title pillText rows =
    if List.isEmpty rows then
        Html.text ""

    else
        Html.div [ Attr.class "cookie-diff-section" ]
            (Html.div [ Attr.class "cookie-diff-section-header" ]
                [ Html.span [ Attr.class "cookie-diff-section-title" ] [ Html.text title ]
                , case pillText of
                    Just t ->
                        Html.span [ Attr.class "cookie-diff-section-pill" ] [ Html.text t ]

                    Nothing ->
                        Html.text ""
                ]
                :: List.concatMap diffKeyRows rows
            )


{-| Render one key/value pair as 1 or 2 diff rows.
-}
diffKeyRows : ( String, String, KeyDiff ) -> List (Html Msg)
diffKeyRows ( key, value, diff ) =
    case diff of
        KeyNew ->
            [ keyAddedRow key value ]

        KeyUnchanged ->
            [ keyUnchangedRow key value ]

        KeyChanged prevValue ->
            [ keyRemovedRow key prevValue
            , keyAddedRow key value
            ]

        KeyRemoved prevValue ->
            [ keyRemovedRow key prevValue ]


keyAddedRow : String -> String -> Html Msg
keyAddedRow key value =
    Html.div [ Attr.class "cookie-kv-row cookie-kv-row-added" ]
        [ Html.span [ Attr.class "cookie-raw-sign" ] [ Html.text "+" ]
        , Html.span [ Attr.class "cookie-kv-key" ] [ Html.text (key ++ ":") ]
        , Html.span [ Attr.class "cookie-kv-value" ] [ Html.text value ]
        ]


keyRemovedRow : String -> String -> Html Msg
keyRemovedRow key value =
    Html.div [ Attr.class "cookie-kv-row cookie-kv-row-removed" ]
        [ Html.span [ Attr.class "cookie-raw-sign" ] [ Html.text "−" ]
        , Html.span [ Attr.class "cookie-kv-key" ] [ Html.text (key ++ ":") ]
        , Html.span [ Attr.class "cookie-kv-value" ] [ Html.text value ]
        ]


keyUnchangedRow : String -> String -> Html Msg
keyUnchangedRow key value =
    Html.div [ Attr.class "cookie-kv-row cookie-kv-row-unchanged" ]
        [ Html.span [ Attr.class "cookie-raw-sign" ] [ Html.text " " ]
        , Html.span [ Attr.class "cookie-kv-key" ] [ Html.text (key ++ ":") ]
        , Html.span [ Attr.class "cookie-kv-value" ] [ Html.text value ]
        ]






encodeTargetSelector : TargetSelector -> Encode.Value
encodeTargetSelector target =
    case target of
        ByTagAndText tag text ->
            Encode.object
                [ ( "type", Encode.string "tag-text" )
                , ( "tag", Encode.string tag )
                , ( "text", Encode.string text )
                ]

        ByFormField formId fieldName ->
            Encode.object
                [ ( "type", Encode.string "form-field" )
                , ( "formId", Encode.string formId )
                , ( "fieldName", Encode.string fieldName )
                ]

        ByLabelText labelText ->
            Encode.object
                [ ( "type", Encode.string "label-text" )
                , ( "text", Encode.string labelText )
                ]

        ById id ->
            Encode.object
                [ ( "type", Encode.string "id" )
                , ( "id", Encode.string id )
                ]

        ByTag tag ->
            Encode.object
                [ ( "type", Encode.string "tag" )
                , ( "tag", Encode.string tag )
                ]

        BySelectors selectors ->
            encodeAssertionHighlight selectors []


encodeAssertionHighlight : List AssertionSelector -> List (List AssertionSelector) -> Encode.Value
encodeAssertionHighlight selectors scopeSelectors =
    Encode.object
        [ ( "type", Encode.string "assertion" )
        , ( "selectors", Encode.list encodeAssertionSelector selectors )
        , ( "scopes", Encode.list (Encode.list encodeAssertionSelector) scopeSelectors )
        ]


encodeInteractionHighlight : List AssertionSelector -> List (List AssertionSelector) -> Encode.Value
encodeInteractionHighlight selectors scopeSelectors =
    Encode.object
        [ ( "type", Encode.string "interaction-selectors" )
        , ( "selectors", Encode.list encodeAssertionSelector selectors )
        , ( "scopes", Encode.list (Encode.list encodeAssertionSelector) scopeSelectors )
        ]


encodeAssertionSelector : AssertionSelector -> Encode.Value
encodeAssertionSelector sel =
    case sel of
        ByText s ->
            Encode.object
                [ ( "kind", Encode.string "text" )
                , ( "value", Encode.string s )
                ]

        ByClass s ->
            Encode.object
                [ ( "kind", Encode.string "class" )
                , ( "value", Encode.string s )
                ]

        ById_ s ->
            Encode.object
                [ ( "kind", Encode.string "id" )
                , ( "value", Encode.string s )
                ]

        ByTag_ s ->
            Encode.object
                [ ( "kind", Encode.string "tag" )
                , ( "value", Encode.string s )
                ]

        ByValue s ->
            Encode.object
                [ ( "kind", Encode.string "value" )
                , ( "value", Encode.string s )
                ]

        ByContaining inner ->
            Encode.object
                [ ( "kind", Encode.string "containing" )
                , ( "selectors", Encode.list encodeAssertionSelector inner )
                ]

        ByOther label ->
            Encode.object
                [ ( "kind", Encode.string "other" )
                , ( "label", Encode.string label )
                ]


truncatePreview : Int -> String -> String
truncatePreview maxLen s =
    if String.length s <= maxLen then
        s

    else
        String.left maxLen s ++ "..."


{-| Pretty-print a string as JSON if it looks like JSON, otherwise return as-is.
-}
formatJsonPreview : String -> String
formatJsonPreview s =
    let
        trimmed =
            String.trim s
    in
    if String.startsWith "{" trimmed || String.startsWith "[" trimmed then
        case Decode.decodeString Decode.value trimmed of
            Ok value ->
                Encode.encode 2 value

            Err _ ->
                s

    else
        s


{-| Whether a step at the given index is a "child" (an assertion that follows
a non-assertion step).
-}
isChildStep : Int -> List Snapshot -> Bool
isChildStep i snapshots =
    if i <= 0 then
        False

    else
        case List.drop i snapshots |> List.head of
            Just s ->
                if s.stepKind /= Assertion then
                    False

                else
                    -- Don't treat as child if the parent would be in a different named group
                    let
                        parentIdx =
                            parentOfChildHelp (i - 1) snapshots

                        parentGroupLabel =
                            snapshots |> List.drop parentIdx |> List.head |> Maybe.andThen .groupLabel
                    in
                    s.groupLabel == parentGroupLabel

            Nothing ->
                False


{-| Find the parent step index for a child step (the nearest preceding
non-child step).
-}
parentOfChild : Int -> List Snapshot -> Int
parentOfChild i snapshots =
    parentOfChildHelp i snapshots


parentOfChildHelp : Int -> List Snapshot -> Int
parentOfChildHelp i snapshots =
    if i <= 0 then
        0

    else
        case List.drop i snapshots |> List.head of
            Just s ->
                if s.stepKind == Assertion then
                    parentOfChildHelp (i - 1) snapshots

                else
                    i

            Nothing ->
                i


{-| Find the next non-child step index at or after the given index.
-}
nextParentStep : Int -> Int -> List Snapshot -> Int
nextParentStep current maxIndex snapshots =
    let
        next =
            current + 1
    in
    if next > maxIndex then
        current

    else if isChildStep next snapshots then
        nextParentStep next maxIndex snapshots

    else
        next


{-| Find the previous non-child step index at or before the given index.
-}
prevParentStep : Int -> List Snapshot -> Int
prevParentStep current snapshots =
    let
        prev =
            current - 1
    in
    if prev < 0 then
        0

    else if isChildStep prev snapshots then
        prevParentStep prev snapshots

    else
        prev


{-| Find the next visible step, respecting expanded groups.
Expanded children are navigable; collapsed children are skipped.
-}
nextVisibleStep : Int -> Int -> List Snapshot -> Set Int -> Int
nextVisibleStep current maxIndex snapshots expanded =
    nextVisibleStepHelp current current maxIndex snapshots expanded


nextVisibleStepHelp : Int -> Int -> Int -> List Snapshot -> Set Int -> Int
nextVisibleStepHelp original current maxIndex snapshots expanded =
    let
        next =
            current + 1
    in
    if next > maxIndex then
        original

    else if isChildStep next snapshots && not (Set.member (parentOfChild next snapshots) expanded) then
        nextVisibleStepHelp original next maxIndex snapshots expanded

    else if isHiddenByNamedGroup next snapshots expanded then
        nextVisibleStepHelp original next maxIndex snapshots expanded

    else
        next


{-| Find the previous visible step, respecting expanded groups.
Expanded children are navigable; collapsed children are skipped.
-}
prevVisibleStep : Int -> List Snapshot -> Set Int -> Int
prevVisibleStep current snapshots expanded =
    prevVisibleStepHelp current current snapshots expanded


prevVisibleStepHelp : Int -> Int -> List Snapshot -> Set Int -> Int
prevVisibleStepHelp original current snapshots expanded =
    let
        prev =
            current - 1
    in
    if prev < 0 then
        original

    else if isChildStep prev snapshots && not (Set.member (parentOfChild prev snapshots) expanded) then
        -- Child of a collapsed group: skip past it
        prevVisibleStepHelp original prev snapshots expanded

    else if isHiddenByNamedGroup prev snapshots expanded then
        prevVisibleStepHelp original prev snapshots expanded

    else
        prev


{-| Count the number of consecutive child (assertion) steps following a
given parent index.
-}
childCount : Int -> List Snapshot -> Int
childCount parentIndex snapshots =
    let
        parentGroupLabel =
            snapshots |> List.drop parentIndex |> List.head |> Maybe.andThen .groupLabel
    in
    snapshots
        |> List.drop (parentIndex + 1)
        |> List.foldl
            (\s ( count, continue ) ->
                if continue && s.stepKind == Assertion && s.groupLabel == parentGroupLabel then
                    ( count + 1, True )

                else
                    ( count, False )
            )
            ( 0, True )
        |> Tuple.first



{-| Check if a step is hidden because its named group is collapsed.
-}
isHiddenByNamedGroup : Int -> List Snapshot -> Set Int -> Bool
isHiddenByNamedGroup i snapshots expanded =
    case snapshots |> List.drop i |> List.head |> Maybe.andThen .groupLabel of
        Just _ ->
            let
                groupStart =
                    namedGroupStart i snapshots
            in
            not (Set.member (-(groupStart + 1)) expanded)

        Nothing ->
            False


{-| Compute the set of snapshot indices that start a new named group.
-}
computeNamedGroupStarts : List Snapshot -> Set Int
computeNamedGroupStarts snapshots =
    snapshots
        |> List.indexedMap Tuple.pair
        |> List.foldl
            (\( i, snap ) acc ->
                case snap.groupLabel of
                    Just name ->
                        let
                            prevLabel =
                                if i == 0 then
                                    Nothing

                                else
                                    snapshots
                                        |> List.drop (i - 1)
                                        |> List.head
                                        |> Maybe.andThen .groupLabel
                        in
                        if prevLabel /= Just name then
                            Set.insert i acc

                        else
                            acc

                    Nothing ->
                        acc
            )
            Set.empty


{-| Initial `expandedGroups` set so every named group is expanded on load.
Uses the negated-key convention the named-group toggle uses: key `-(i + 1)`
for the snapshot at index `i` that starts the group.
-}
defaultExpandedGroups : List Snapshot -> Set Int
defaultExpandedGroups snapshots =
    computeNamedGroupStarts snapshots
        |> Set.toList
        |> List.map (\i -> -(i + 1))
        |> Set.fromList


{-| Find the index of the first snapshot in the same named group.
-}
namedGroupStart : Int -> List Snapshot -> Int
namedGroupStart i snapshots =
    let
        targetLabel =
            snapshots
                |> List.drop i
                |> List.head
                |> Maybe.andThen .groupLabel
    in
    case targetLabel of
        Nothing ->
            i

        Just label ->
            namedGroupStartHelp (i - 1) label snapshots


namedGroupStartHelp : Int -> String -> List Snapshot -> Int
namedGroupStartHelp i label snapshots =
    if i < 0 then
        0

    else
        case snapshots |> List.drop i |> List.head |> Maybe.andThen .groupLabel of
            Just l ->
                if l == label then
                    namedGroupStartHelp (i - 1) label snapshots

                else
                    i + 1

            Nothing ->
                i + 1


{-| Count snapshots in a named group starting at the given index.
-}
namedGroupChildCount : Int -> List Snapshot -> Int
namedGroupChildCount startIndex snapshots =
    let
        targetLabel =
            snapshots
                |> List.drop startIndex
                |> List.head
                |> Maybe.andThen .groupLabel
    in
    case targetLabel of
        Nothing ->
            0

        Just label ->
            snapshots
                |> List.drop startIndex
                |> List.foldl
                    (\s ( count, continue ) ->
                        if continue && s.groupLabel == Just label then
                            ( count + 1, True )

                        else
                            ( count, False )
                    )
                    ( 0, True )
                |> Tuple.first


{-| Render a named group header row.
-}
viewNamedGroupHeader : Int -> String -> Bool -> Int -> Html Msg
viewNamedGroupHeader groupStartIndex name isExpanded count =
    Html.div
        [ Attr.class "named-group-header"
        , Html.Events.onClick (ToggleGroup (-(groupStartIndex + 1)))
        ]
        [ Html.span [ Attr.class "named-group-icon" ]
            [ Html.text
                (if isExpanded then
                    "\u{25BE}"

                 else
                    "\u{25B8}"
                )
            ]
        , Html.span [ Attr.class "named-group-name" ]
            [ Html.text name ]
        , Html.span [ Attr.class "named-group-count" ]
            [ Html.text ("(" ++ String.fromInt count ++ ")") ]
        ]


-- CSS


css : String
css =
    """
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #1a1a2e;
    color: #e0e0e0;
    height: 100vh;
    overflow: hidden;
}

.viewer {
    display: flex;
    flex-direction: column;
    height: 100vh;
}

/* === HEADER === */

.viewer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 16px;
    background: #16213e;
    border-bottom: 1px solid #0f3460;
    flex-shrink: 0;
}

.header-left {
    display: flex;
    align-items: center;
    gap: 4px;
}

.header-logo {
    color: #4cc9f0;
    font-weight: 700;
    font-size: 14px;
}

.header-title {
    color: #8899aa;
    font-size: 14px;
}

.header-center {
    flex: 1;
    display: flex;
    justify-content: center;
    overflow-x: auto;
}

.test-name {
    color: #4cc9f0;
    font-weight: 600;
    font-size: 14px;
}

.header-right {
    display: flex;
    align-items: center;
    gap: 8px;
}

.step-counter {
    color: #8899aa;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
}

.viewport-picker {
    display: flex;
    gap: 2px;
    margin-right: 8px;
}

.viewport-btn {
    padding: 3px 8px;
    border: 1px solid #0f3460;
    background: transparent;
    color: #556677;
    border-radius: 3px;
    cursor: pointer;
    font-size: 11px;
    font-variant-numeric: tabular-nums;
}

.viewport-btn:hover {
    background: #0f3460;
    color: #8899aa;
}

.viewport-btn-active {
    background: #0f3460;
    color: #4cc9f0;
    border-color: #4cc9f0;
}

.toggle-button {
    padding: 4px 10px;
    border: 1px solid #0f3460;
    background: transparent;
    color: #8899aa;
    border-radius: 4px;
    cursor: pointer;
    font-size: 12px;
}

.toggle-button:hover {
    background: #0f3460;
    color: #e0e0e0;
}

.toggle-active {
    background: #0f3460;
    color: #4cc9f0;
    border-color: #4cc9f0;
}

/* === BODY (sidebar + main) === */

.viewer-body {
    flex: 1;
    display: flex;
    overflow: hidden;
}

/* === SIDEBAR === */

.sidebar {
    width: 320px;
    min-width: 320px;
    display: flex;
    flex-direction: column;
    background: #16213e;
    border-right: 1px solid #0f3460;
}

.sidebar-header {
    padding: 10px 12px 8px;
    border-bottom: 1px solid #0f3460;
}

.sidebar-title {
    font-size: 11px;
    color: #556677;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.sidebar-steps {
    flex: 1;
    overflow-y: auto;
    padding: 4px 0;
}

.step-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    cursor: pointer;
    border-left: 3px solid transparent;
    transition: background 0.08s, border-color 0.08s;
}

.step-row:hover {
    background: rgba(76, 201, 240, 0.06);
}

.step-row-active {
    background: rgba(76, 201, 240, 0.1);
    border-left-color: #4cc9f0;
}

.step-row-hovered {
    background: rgba(76, 201, 240, 0.15);
    border-left-color: rgba(76, 201, 240, 0.5);
}

.step-row-past {
    opacity: 0.65;
}

.step-row-error {
    background: rgba(231, 76, 60, 0.1);
    border-left-color: #e74c3c;
}

/* Step that caused the failure — the step *before* the error. Reads as
   amber so it's distinct from the red error row itself. */
.step-row-failure-cause {
    border-left-color: #fcd34d;
    background: rgba(252, 211, 77, 0.06);
    box-shadow: inset 0 -1px 0 rgba(252, 211, 77, 0.18);
}

.step-row-failure-cause .step-label-selector {
    color: #fcd34d;
}

.step-row-child {
    padding-left: 28px;
    font-size: 11px;
}

.step-row-child .step-number {
    font-size: 10px;
    color: #445566;
}

.step-row-child .step-label {
    font-size: 11px;
    color: #8a9aaa;
}

.step-number {
    font-size: 11px;
    color: #556677;
    min-width: 20px;
    text-align: right;
    font-variant-numeric: tabular-nums;
}

.step-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 14px;
    width: 18px;
    height: 14px;
    flex-shrink: 0;
}

.step-icon svg {
    display: block;
    overflow: visible;
}

.step-event-dots {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    margin-left: 6px;
    flex-shrink: 0;
    opacity: 0.85;
}

.step-row:hover .step-event-dots,
.step-row-active .step-event-dots {
    opacity: 1;
}

.step-event-dot {
    display: inline-flex;
    align-items: center;
    gap: 2px;
}

.step-event-dot svg {
    display: block;
}

.step-event-count {
    font-family: "SF Mono", "JetBrains Mono", "Fira Code", monospace;
    font-size: 9px;
    font-weight: 600;
    line-height: 1;
}

.step-label {
    font-size: 12px;
    color: #c0c8d0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    flex: 1;
}

.step-row-active .step-label {
    color: #e0e8f0;
    font-weight: 500;
}

.step-row-error .step-label {
    color: #e74c3c;
    font-weight: 600;
}

.step-label-fn {
    color: #8a9aaa;
}

.step-label-selector {
    color: #7ee787;
    font-weight: 500;
}

.step-row-active .step-label-selector {
    color: #a5f0a5;
    font-weight: 600;
}

.step-label-scope {
    color: #6a7a8a;
    font-style: italic;
    font-size: 11px;
}

/* === TEST LIST === */

.test-list-row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    cursor: pointer;
    border-left: 3px solid transparent;
    transition: background 0.08s;
}

.test-list-row:hover {
    background: rgba(76, 201, 240, 0.06);
}

.test-list-row-selected {
    background: rgba(76, 201, 240, 0.1);
    border-left-color: #4cc9f0;
}

.test-list-row-error {
    border-left-color: #e74c3c;
}

.test-list-indicator {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    font-weight: 700;
    min-width: 16px;
    text-align: center;
}

.test-list-info {
    flex: 1;
    min-width: 0;
}

.test-list-name {
    font-size: 13px;
    color: #c0c8d0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.test-list-row-selected .test-list-name {
    color: #e0e8f0;
    font-weight: 500;
}

.test-list-meta {
    font-size: 11px;
    color: #556677;
    margin-top: 2px;
}

.search-input {
    display: block;
    width: 100%;
    margin-top: 8px;
    padding: 5px 8px;
    background: #0d1117;
    border: 1px solid #0f3460;
    border-radius: 4px;
    color: #c0c8d0;
    font-size: 12px;
    outline: none;
}

.search-input:focus {
    border-color: #4cc9f0;
}

.search-input::placeholder {
    color: #556677;
}

.sidebar-back {
    display: block;
    width: 100%;
    text-align: left;
    padding: 6px 0;
    border: none;
    background: transparent;
    color: #4cc9f0;
    font-size: 12px;
    cursor: pointer;
    margin-bottom: 4px;
}

.sidebar-back:hover {
    color: #7dd8f5;
}

.header-summary {
    font-size: 13px;
    color: #8899aa;
}

.step-group-toggle {
    font-size: 10px;
    color: #556677;
    background: rgba(126, 231, 135, 0.1);
    padding: 1px 6px;
    border-radius: 3px;
    cursor: pointer;
    margin-left: auto;
    white-space: nowrap;
}

.step-group-toggle:hover {
    background: rgba(126, 231, 135, 0.2);
    color: #7ee787;
}

/* Named group headers */

.named-group-header {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 10px 6px 12px;
    cursor: pointer;
    background: transparent;
    border-left: 3px solid transparent;
    background-image: linear-gradient(180deg, rgba(125, 211, 252, 0.25), rgba(134, 239, 172, 0.18));
    background-repeat: no-repeat;
    background-size: 3px 100%;
    background-position: left center;
    font-size: 10px;
    color: #8b99ad;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    font-weight: 600;
    margin-top: 4px;
}

.named-group-header:hover {
    background-color: rgba(125, 211, 252, 0.04);
}

.named-group-icon {
    font-size: 8px;
    opacity: 0.6;
    color: currentColor;
}

.named-group-name {
    font-weight: 600;
    color: #e6ecf4;
}

.named-group-count {
    margin-left: auto;
    font-size: 9px;
    font-weight: 400;
    color: inherit;
    opacity: 0.55;
    background: transparent;
    padding: 0;
}

/* === MAIN PANEL === */

.main-panel {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background: #1a1a2e;
}

.main-panel-content {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

/* === URL BAR === */

.url-bar-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 8px 12px 0;
    flex-shrink: 0;
}

.url-bar-row .url-bar {
    flex: 1;
    margin: 0;
}

.url-bar {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 8px 12px 0;
    padding: 6px 12px;
    background: #0d1117;
    border: 1px solid #0f3460;
    border-radius: 6px;
    flex-shrink: 0;
}

.url-bar-icon {
    color: #556677;
    font-size: 12px;
}

.url-bar-text {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    color: #8899aa;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

/* === RENDERED PAGE === */

.rendered-page {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background: #ffffff;
    color: #1a1a1a;
    margin: 8px 12px;
    border-radius: 8px;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.3);
}

.page-title-bar {
    padding: 8px 16px;
    background: #f0f0f0;
    border-bottom: 1px solid #ddd;
    font-size: 12px;
    color: #666;
    border-radius: 8px 8px 0 0;
    display: flex;
    align-items: center;
    gap: 8px;
}

.page-title-dots {
    display: flex;
    gap: 5px;
    margin-right: 4px;
}

.dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
}

.dot-red { background: #ff5f57; }
.dot-yellow { background: #ffbd2e; }
.dot-green { background: #28c840; }

.page-body {
    display: none;
}

#preview-iframe {
    flex: 1;
    width: 100%;
    border: none;
    background: #ffffff;
}

.rendered-page-before {
    outline: 2px solid rgba(231, 76, 60, 0.5);
    outline-offset: -2px;
}

.rendered-page-before .page-body {
    background: rgba(231, 76, 60, 0.03);
}

.rendered-page-after {
    outline: 2px solid rgba(126, 231, 135, 0.5);
    outline-offset: -2px;
}

.rendered-page-after .page-body {
    background: rgba(126, 231, 135, 0.03);
}

.preview-mode-badge {
    margin-left: auto;
    font-size: 10px;
    font-weight: 700;
    padding: 1px 8px;
    border-radius: 3px;
    letter-spacing: 0.5px;
}

.preview-mode-before {
    background: rgba(231, 76, 60, 0.15);
    color: #e74c3c;
}

.preview-mode-after {
    background: rgba(126, 231, 135, 0.15);
    color: #7ee787;
}

/* === NETWORK SIDEBAR (N1 · list with live state chips) === */

.network-sidebar {
    width: 340px;
    min-width: 340px;
    display: flex;
    flex-direction: column;
    background: #141a22;
    border-left: 1px solid rgba(255, 255, 255, 0.08);
    overflow: hidden;
    font-family: "JetBrains Mono", "SF Mono", monospace;
}

.network-sidebar-header {
    padding: 10px 14px 8px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    display: flex;
    flex-direction: column;
    gap: 6px;
    flex-shrink: 0;
}

.network-sidebar-title-row {
    display: flex;
    align-items: baseline;
    gap: 8px;
}

.sidebar-subtitle {
    font-size: 11px;
    color: #5c6a7e;
}

.net-live-count {
    color: #86efac;
    font-weight: 600;
}

.net-filter-buttons {
    display: flex;
    gap: 4px;
}

.net-filter-btn {
    font-size: 10px;
    padding: 2px 8px;
    border-radius: 10px;
    border: 1px solid rgba(255, 255, 255, 0.12);
    background: transparent;
    color: #5c6a7e;
    cursor: pointer;
    font-family: inherit;
}

.net-filter-btn:hover {
    color: #c9d1d9;
    border-color: #484f58;
}

.net-filter-backend.net-filter-active {
    background: rgba(244, 114, 182, 0.15);
    border-color: #f472b6;
    color: #f472b6;
}

.net-filter-frontend.net-filter-active {
    background: rgba(125, 211, 252, 0.15);
    border-color: #7dd3fc;
    color: #7dd3fc;
}

.network-empty {
    padding: 14px;
    color: #5c6a7e;
    font-size: 12px;
    font-style: italic;
}

.network-list {
    flex: 1;
    overflow-y: auto;
    padding: 0;
}

.net-row {
    padding: 6px 14px 8px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.05);
    position: relative;
    transition: background 0.08s;
}

.net-row[open] > .net-row-summary,
.net-row.net-row-summary {
    list-style: none;
}

.net-row-summary {
    list-style: none;
    cursor: pointer;
    user-select: none;
}

.net-row-summary::-webkit-details-marker {
    display: none;
}

.net-row-summary::marker {
    content: "";
}

.net-row-summary:hover {
    color: #c9d1d9;
}

.net-row-future {
    opacity: 0.5;
}

/* Same phase-sync trick as `.fetcher-card`: attach the pulse
   pseudo-element to every row, colorize only on in-flight ones. */
.net-row::before {
    content: "";
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 3px;
    background: transparent;
    animation: net-pulse 1.2s ease-in-out infinite;
    pointer-events: none;
}

.net-row-inflight {
    background: rgba(134, 239, 172, 0.12);
}

.net-row-inflight::before {
    background: #86efac;
    box-shadow: 0 0 10px rgba(134, 239, 172, 0.8);
}

.net-row-resolving {
    background: rgba(125, 211, 252, 0.05);
}

.net-row-head {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 3px;
}

.net-row-chips {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-left: 18px;
    flex-wrap: wrap;
}

.net-row-path {
    font-size: 11px;
    color: #e6ecf4;
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.net-row-future .net-row-path {
    color: #5c6a7e;
}

.net-method {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    font-weight: 700;
    padding: 1px 4px;
    border-radius: 2px;
    flex-shrink: 0;
    letter-spacing: 0.02em;
}

.net-method-port {
    background: rgba(244, 114, 182, 0.15);
    color: #f472b6;
}

.net-method-http {
    background: rgba(125, 211, 252, 0.15);
    color: #7dd3fc;
}

.net-state-badge {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    border-radius: 2px;
    font-size: 9px;
    font-weight: 600;
    padding: 1px 4px;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    font-family: "JetBrains Mono", monospace;
}

.net-state-icon {
    font-size: 9px;
    line-height: 1;
}

.net-state-future {
    background: transparent;
    color: #5c6a7e;
}

.net-state-inflight {
    background: rgba(134, 239, 172, 0.15);
    color: #86efac;
}

.net-state-resolving {
    background: rgba(125, 211, 252, 0.15);
    color: #7dd3fc;
}

.net-state-past {
    background: transparent;
    color: #8b99ad;
}

.net-row-inflight-text {
    font-size: 9px;
    color: #86efac;
    font-family: "JetBrains Mono", monospace;
    font-style: italic;
}

.net-row-chip-arrow-live {
    color: #86efac;
    opacity: 0.7;
}

.net-row-live-badge {
    margin-left: auto;
    font-size: 9px;
    color: #86efac;
    font-weight: 600;
    letter-spacing: 0.04em;
}

.net-row-details {
    padding: 6px 0 2px 18px;
    display: flex;
    flex-direction: column;
    gap: 4px;
}

@keyframes net-pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.25; }
}

.net-response-details {
    margin-top: 4px;
}

.net-response-summary {
    font-size: 10px;
    color: #8899aa;
    cursor: pointer;
    user-select: none;
}

.net-response-summary:hover {
    color: #aabbcc;
}

.net-response-body {
    font-size: 10px;
    color: #c8d6e5;
    background: rgba(0, 0, 0, 0.2);
    padding: 6px 8px;
    border-radius: 4px;
    margin: 4px 0 0;
    max-height: 200px;
    overflow: auto;
    white-space: pre-wrap;
    word-break: break-all;
}

.net-request-summary {
    color: #4cc9f0;
}

.net-headers-summary {
    color: #a88beb;
}

.net-headers-list {
    padding: 4px 8px;
    margin: 4px 0 0;
    background: rgba(0, 0, 0, 0.2);
    border-radius: 4px;
    font-size: 10px;
}

.net-header-row {
    padding: 1px 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.net-header-name {
    color: #a88beb;
    font-weight: 600;
}

.net-header-value {
    color: #c8d6e5;
}

/* === BEFORE/AFTER TOGGLE === */

.before-after-toggle {
    display: inline-flex;
    align-items: center;
    gap: 0;
    flex-shrink: 0;
}

.ba-btn {
    padding: 4px 10px;
    border: 1px solid #0f3460;
    background: #16213e;
    color: #8899aa;
    font-size: 11px;
    font-family: "SF Mono", "JetBrains Mono", "Fira Code", monospace;
    letter-spacing: 0.04em;
    cursor: pointer;
    transition: all 0.1s;
}

.ba-btn:first-child {
    border-radius: 4px 0 0 4px;
}

.ba-btn:last-child {
    border-radius: 0 4px 4px 0;
}

.ba-btn:hover {
    background: #1a2a4e;
    color: #c0c8d0;
}

.ba-btn-active {
    background: #4cc9f0;
    color: #0d1117;
    border-color: #4cc9f0;
    font-weight: 600;
}

/* === COOKIE SIDEBAR (Variant B · stacked value history) === */

.cookie-sidebar {
    width: 340px;
    min-width: 340px;
    display: flex;
    flex-direction: column;
    background: #141a22;
    border-left: 1px solid rgba(255, 255, 255, 0.08);
    overflow: hidden;
    font-family: "JetBrains Mono", "SF Mono", monospace;
}

.cookie-sidebar-header {
    padding: 10px 14px 8px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    display: flex;
    align-items: baseline;
    gap: 8px;
    flex-shrink: 0;
}

.cookie-empty {
    padding: 14px;
    color: #5c6a7e;
    font-size: 12px;
    font-style: italic;
}

.cookie-list {
    overflow-y: auto;
    padding: 0;
}

.cookie-stack {
    padding: 10px 14px 14px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.cookie-stack-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 6px;
}

.cookie-name {
    font-family: "JetBrains Mono", monospace;
    font-size: 13px;
    font-weight: 600;
    color: #7dd3fc;
}

.cookie-signed-badge {
    font-size: 9px;
    font-weight: 600;
    padding: 1px 5px;
    border-radius: 3px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    background: rgba(125, 211, 252, 0.14);
    color: #7dd3fc;
}

.cookie-stack-count {
    margin-left: auto;
    font-size: 10px;
    color: #5c6a7e;
}

.cookie-secret-label {
    font-size: 10px;
    color: #8b99ad;
    margin: 0 0 8px;
    display: flex;
    gap: 4px;
    align-items: baseline;
}

.cookie-secret-label code {
    background: rgba(125, 211, 252, 0.08);
    color: #7dd3fc;
    padding: 1px 4px;
    border-radius: 3px;
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
}

.cookie-fnv-note {
    font-size: 9px;
    color: #5c6a7e;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    font-family: "JetBrains Mono", monospace;
    padding: 1px 4px;
    border: 1px dashed rgba(255, 255, 255, 0.12);
    border-radius: 3px;
}

.cookie-stack-empty {
    font-size: 11px;
    color: #5c6a7e;
    font-style: italic;
    padding: 4px 0 0 4px;
}

/* C3 "box pills" step selector that sits above the stacked value rows. */
.cookie-pill-row {
    display: flex;
    flex-wrap: wrap;
    gap: 3px;
    margin-bottom: 8px;
}

.cookie-box-pill {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-left-width: 3px;
    background: transparent;
    color: #8b99ad;
    padding: 2px 6px;
    border-radius: 3px;
    cursor: pointer;
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    font-weight: 500;
    line-height: 1.4;
}

.cookie-box-pill:hover {
    color: #e6ecf4;
    border-color: rgba(255, 255, 255, 0.18);
}

.cookie-box-pill-kind-set {
    border-left-color: #86efac;
}

.cookie-box-pill-kind-changed {
    border-left-color: #fcd34d;
}

.cookie-box-pill-kind-removed {
    border-left-color: #fca5a5;
}

/* Active pill: set the three non-left borders explicitly so the left border
   keeps the event-kind color set by the `.cookie-box-pill-kind-*` class. */
.cookie-box-pill-active {
    background: rgba(125, 211, 252, 0.12);
    border-top-color: #7dd3fc;
    border-right-color: #7dd3fc;
    border-bottom-color: #7dd3fc;
    color: #7dd3fc;
    font-weight: 600;
}

.cookie-box-pill-step {
    font-variant-numeric: tabular-nums;
}

.cookie-box-pill-now {
    font-size: 8px;
    color: #5c6a7e;
    letter-spacing: 0.04em;
}

.cookie-box-pill-active .cookie-box-pill-now {
    color: #7dd3fc;
}

/* Header event pill on the cookie name row (SET / CHANGED / REMOVED). */
.cookie-event-badge {
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.08em;
    padding: 1px 6px;
    border-radius: 3px;
    font-family: "JetBrains Mono", monospace;
    text-transform: uppercase;
}

.cookie-event-badge-set {
    background: rgba(134, 239, 172, 0.14);
    color: #86efac;
}

.cookie-event-badge-changed {
    background: rgba(252, 211, 77, 0.14);
    color: #fcd34d;
}

.cookie-event-badge-removed {
    background: rgba(252, 165, 165, 0.14);
    color: #fca5a5;
}

/* Single diff card per cookie: INITIAL / DIFF / REMOVED panel. */
.cookie-diff-card {
    background: #141a22;
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 5px;
    padding: 10px 12px;
    font-family: "JetBrains Mono", monospace;
}

.cookie-diff-card-title {
    font-size: 10px;
    color: #5c6a7e;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    margin-bottom: 8px;
}

.cookie-diff-section {
    margin-bottom: 8px;
}

.cookie-diff-section:last-child {
    margin-bottom: 0;
}

.cookie-diff-section-header {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 10px;
    color: #8b99ad;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    margin-bottom: 4px;
}

.cookie-diff-section-pill {
    font-size: 8px;
    font-weight: 700;
    padding: 1px 5px;
    border-radius: 2px;
    background: rgba(196, 181, 253, 0.18);
    color: #c4b5fd;
    letter-spacing: 0.06em;
    text-transform: uppercase;
}

.cookie-kv-row,
.cookie-raw-row {
    display: flex;
    align-items: baseline;
    gap: 6px;
    font-family: "JetBrains Mono", monospace;
    font-size: 12px;
    padding: 1px 0;
}

.cookie-raw-sign {
    font-weight: 700;
    font-size: 12px;
    min-width: 10px;
    text-align: center;
    flex-shrink: 0;
}

.cookie-kv-row-added .cookie-raw-sign,
.cookie-raw-row-added .cookie-raw-sign,
.cookie-kv-row-added .cookie-kv-key,
.cookie-kv-row-added .cookie-kv-value,
.cookie-raw-row-added .cookie-raw-value-text {
    color: #86efac;
}

.cookie-kv-row-removed .cookie-raw-sign,
.cookie-raw-row-removed .cookie-raw-sign,
.cookie-kv-row-removed .cookie-kv-key,
.cookie-kv-row-removed .cookie-kv-value,
.cookie-raw-row-removed .cookie-raw-value-text {
    color: #fca5a5;
    text-decoration: line-through;
}

.cookie-kv-row-unchanged .cookie-kv-key {
    color: #8b99ad;
}

.cookie-kv-row-unchanged .cookie-kv-value {
    color: #c9d1d9;
}

.cookie-kv-key {
    font-weight: 600;
}

.cookie-kv-value {
    word-break: break-all;
}

.cookie-raw-value-text {
    word-break: break-all;
}

/* No-change cookies section at the bottom of the sidebar. */
.cookie-nochange-section {
    padding: 10px 14px 14px;
}

.cookie-nochange-header {
    font-size: 10px;
    color: #5c6a7e;
    letter-spacing: 0.05em;
    margin-bottom: 6px;
    font-family: "JetBrains Mono", monospace;
}

.cookie-nochange-row {
    display: flex;
    align-items: baseline;
    gap: 6px;
    font-size: 11px;
    color: #8b99ad;
    padding: 2px 0;
    font-family: "JetBrains Mono", monospace;
}

.cookie-nochange-row .cookie-name {
    font-size: 11px;
    color: #7dd3fc;
    font-weight: 600;
}

.cookie-nochange-sep {
    color: #5c6a7e;
}

.cookie-nochange-value {
    color: #c9d1d9;
    word-break: break-all;
}

.cookie-attr-table {
    margin: 4px 0 0;
    padding: 6px 8px;
    background: rgba(13, 17, 23, 0.5);
    border-radius: 4px;
}

.cookie-attr-row {
    display: grid;
    grid-template-columns: 80px 1fr;
    gap: 8px;
    align-items: baseline;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 11px;
    padding: 1px 0;
}

.cookie-attr-name {
    color: #7dd3fc;
}

.cookie-attr-value {
    color: #c9d1d9;
    word-break: break-all;
}

.cookie-attr-unset {
    color: #6b7280;
}

.cookie-details {
    margin-top: 4px;
}

.cookie-details-summary {
    cursor: pointer;
    font-size: 10px;
    color: #7d8590;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    padding: 2px 0;
}

.cookie-details-summary:hover {
    color: #c9d1d9;
}

.cookie-raw-value {
    margin: 4px 0 0;
    padding: 6px 8px;
    background: #0d1117;
    border-radius: 4px;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 10px;
    color: #c9d1d9;
    white-space: pre-wrap;
    word-break: break-all;
    max-height: 160px;
    overflow: auto;
}

/* === STEP CHIP (shared: cookie/network/fetcher) === */

.step-chip-timeline {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    flex-wrap: wrap;
}

.step-chip-group {
    display: inline-flex;
    align-items: center;
    gap: 2px;
}

.step-chip-arrow {
    color: rgba(255, 255, 255, 0.25);
    font-size: 10px;
    margin: 0 1px;
}

.step-chip {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    border: 1px solid rgba(255, 255, 255, 0.10);
    border-left-width: 3px;
    background: transparent;
    padding: 1px 6px;
    border-radius: 3px;
    cursor: pointer;
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    letter-spacing: 0.02em;
    font-weight: 500;
    line-height: 1.4;
    color: #8b99ad;
}

.step-chip:hover {
    background: rgba(125, 211, 252, 0.08);
}

.step-chip-num {
    font-variant-numeric: tabular-nums;
}

.step-chip-label {
    opacity: 0.75;
    font-size: 9px;
}

.step-chip-now {
    background: rgba(125, 211, 252, 0.14);
    border-color: rgba(125, 211, 252, 0.4);
    border-left-color: #7dd3fc;
    color: #7dd3fc;
    font-weight: 600;
}

.step-chip-start {
    border-left-color: #86efac;
    color: #86efac;
}

.step-chip-end {
    border-left-color: #7dd3fc;
    color: #7dd3fc;
}

.step-chip-change {
    border-left-color: #fcd34d;
    color: #fcd34d;
}

.step-chip-error {
    background: rgba(252, 165, 165, 0.10);
    border-left-color: #fca5a5;
    color: #fca5a5;
}

.step-chip-past {
    border-left-color: rgba(255, 255, 255, 0.12);
    color: #8b99ad;
}

.step-chip-future {
    border-left-color: rgba(255, 255, 255, 0.06);
    color: #5c6a7e;
}

/* === FETCHER INSPECTOR (F1 · chip timeline) === */

.fetcher-inspector {
    flex-shrink: 0;
    max-height: 260px;
    overflow: auto;
    background: #141a22;
    border-top: 1px solid rgba(255, 255, 255, 0.08);
    margin: 0 12px;
    border-radius: 6px 6px 0 0;
    font-family: "JetBrains Mono", "SF Mono", monospace;
}

.fetcher-inspector .inspector-header {
    display: flex;
    align-items: baseline;
    gap: 8px;
    padding: 8px 14px 6px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    text-transform: none;
    letter-spacing: normal;
    color: inherit;
    font-size: inherit;
}

.fetcher-empty {
    padding: 10px 14px 12px;
    color: #5c6a7e;
    font-size: 12px;
    font-style: italic;
}

.fetcher-list {
    padding: 4px 0 8px;
}

.fetcher-card {
    padding: 8px 14px 8px 16px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.05);
    position: relative;
}

/* Every fetcher card renders the pulse bar pseudo-element; its
   color + glow only kick in on `.fetcher-card-live`. Running the
   animation on all cards from first mount keeps the phase aligned
   across cards that become live at different steps. */
.fetcher-card::before {
    content: "";
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 3px;
    background: transparent;
    animation: net-pulse 1.2s ease-in-out infinite;
    pointer-events: none;
}

.fetcher-card-live {
    background: rgba(134, 239, 172, 0.12);
}

.fetcher-card-live::before {
    background: #86efac;
    box-shadow: 0 0 10px rgba(134, 239, 172, 0.8);
}

.fetcher-card-header {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 6px;
}

.fetcher-id {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    color: #e6ecf4;
}

.fetcher-spacer {
    flex: 1;
}

.fetcher-live-badge {
    font-size: 9px;
    color: #86efac;
    font-weight: 600;
    letter-spacing: 0.04em;
}

.fetcher-done-badge {
    font-size: 9px;
    color: #7dd3fc;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 1px 5px;
    border-radius: 3px;
    background: rgba(125, 211, 252, 0.14);
    text-transform: uppercase;
    font-family: "JetBrains Mono", monospace;
}

.fetcher-live-count {
    color: #86efac;
    font-weight: 600;
}

.fetcher-state-label {
    font-size: 9px;
    color: #5c6a7e;
    letter-spacing: 0.05em;
    text-transform: lowercase;
    font-family: "JetBrains Mono", monospace;
}

.fetcher-lanes {
    display: grid;
    grid-template-columns: 62px 1fr;
    row-gap: 3px;
    column-gap: 8px;
    align-items: center;
}

.fetcher-lane {
    display: contents;
}

.fetcher-lane-label {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.1em;
}

.fetcher-lane-submit .fetcher-lane-label {
    color: #86efac;
}

.fetcher-lane-resolve .fetcher-lane-label {
    color: #7dd3fc;
}

.fetcher-lane-body {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 3px 6px;
    border-radius: 3px;
    flex-wrap: wrap;
    min-height: 20px;
}

.fetcher-lane-submit .fetcher-lane-body {
    background: rgba(134, 239, 172, 0.06);
}

.fetcher-lane-resolve .fetcher-lane-body {
    background: rgba(125, 211, 252, 0.06);
}

.fetcher-lane-empty {
    color: #5c6a7e;
    font-size: 10px;
    font-style: italic;
}

.fetcher-fields {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    color: #8b99ad;
    font-style: italic;
}

.fetcher-fields-payload {
    color: #e6ecf4;
    font-style: normal;
}

.effect-inspector {
    flex-shrink: 0;
    max-height: 180px;
    overflow: auto;
    background: #0d1117;
    border-top: 1px solid #0f3460;
    margin: 0 12px;
    border-radius: 6px 6px 0 0;
}

.effect-empty {
    padding: 8px 12px 12px;
    color: #556677;
    font-size: 12px;
    font-style: italic;
}

.effect-list {
    padding: 4px 0 8px;
}

.effect-item {
    padding: 4px 12px;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
}

.effect-method {
    color: #4cc9f0;
    font-weight: 600;
}

.effect-url {
    color: #f0c040;
}

.effect-desc {
    color: #8899aa;
}

/* === MODEL INSPECTOR === */

.model-inspector {
    flex-shrink: 0;
    max-height: 300px;
    overflow: auto;
    background: #0d1117;
    border-top: 1px solid #0f3460;
    margin: 0 12px 8px;
    border-radius: 6px;
}

.inspector-header {
    font-size: 11px;
    color: #556677;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    padding: 8px 12px 4px;
}

.inspector-body {
    padding: 4px 12px 12px;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    color: #c9d1d9;
    line-height: 1.5;
}

/* Debug value tree */

.dv-string { color: #7ee787; }
.dv-number { color: #79c0ff; }
.dv-keyword { color: #d2a8ff; }
.dv-constructor { color: #ffa657; }
.dv-field-name { color: #79c0ff; }
.dv-punct { color: #6e7681; }
.dv-internals { color: #6e7681; font-style: italic; }

.dv-toggle {
    cursor: pointer;
    color: #6e7681;
    user-select: none;
    display: inline;
}

.dv-toggle:hover {
    color: #c9d1d9;
}

.dv-collapsed {
    cursor: pointer;
}

.dv-collapsed:hover {
    background: rgba(110, 118, 129, 0.1);
    border-radius: 3px;
}

.dv-indent {
    padding-left: 16px;
    border-left: 1px solid #21262d;
}

.dv-row {
    padding: 1px 0;
}

.dv-collection,
.dv-record,
.dv-custom {
    display: inline;
}

.dv-inline {
    display: inline;
}

/* === ERROR PANEL === */

.error-panel {
    flex-shrink: 0;
    margin: 8px 12px 0;
    border: 1px solid #e74c3c;
    border-radius: 8px;
    background: #1c0d0d;
    overflow: hidden;
}

.error-panel-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 14px;
    background: rgba(231, 76, 60, 0.15);
    font-size: 13px;
    font-weight: 600;
    color: #e74c3c;
}

.error-panel-icon {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: #e74c3c;
    color: #fff;
    font-size: 11px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
}

.error-panel-body {
    padding: 12px 14px;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    color: #e0a0a0;
    white-space: pre-wrap;
    word-break: break-word;
    max-height: 200px;
    overflow: auto;
}

/* === EMPTY STATE === */

.viewer-empty {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #556677;
    font-size: 16px;
}

/* === KEYBOARD HINT === */

.viewer::after {
    content: "\\2190 \\2192  step   \\2191 \\2193  test   n  network   f  fetchers   e  effects   m  model   esc  back";
    position: fixed;
    bottom: 4px;
    right: 12px;
    font-size: 10px;
    color: #334455;
    pointer-events: none;
}

/* === SCROLLBAR === */

.sidebar-steps::-webkit-scrollbar {
    width: 6px;
}

.sidebar-steps::-webkit-scrollbar-track {
    background: transparent;
}

.sidebar-steps::-webkit-scrollbar-thumb {
    background: #334455;
    border-radius: 3px;
}

.sidebar-steps::-webkit-scrollbar-thumb:hover {
    background: #445566;
}

.rendered-page::-webkit-scrollbar {
    width: 8px;
}

.rendered-page::-webkit-scrollbar-track {
    background: #f0f0f0;
}

.rendered-page::-webkit-scrollbar-thumb {
    background: #ccc;
    border-radius: 4px;
}
"""
