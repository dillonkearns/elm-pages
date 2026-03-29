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

@docs app, Flags, Model, Msg

-}

import Browser
import Browser.Dom
import Browser.Events
import Browser.Navigation as Nav
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)
import Task
import Test.PagesProgram exposing (FetcherEntry, FetcherStatus(..), NetworkEntry, NetworkStatus(..), Snapshot, StepKind(..), TargetSelector(..))
import Test.PagesProgram.Selector exposing (AssertionSelector(..))
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
    , showFetchers : Bool
    , previewMode : PreviewMode
    , expandedGroups : Set Int
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
    | ToggleFetchers
    | SetPreviewMode PreviewMode
    | ToggleGroup Int
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
                  , showFetchers = False
                  , previewMode = After
                  , expandedGroups = Set.empty
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


{-| Extract the base path (e.g., "/__test-viewer") from the initial URL.
This is everything up to and including the viewer route prefix.
-}
extractBasePath : Url -> String
extractBasePath url =
    let
        path =
            url.path
    in
    if String.contains "/__test-viewer" path then
        let
            idx =
                String.indexes "/__test-viewer" path
                    |> List.head
                    |> Maybe.withDefault 0
        in
        String.left (idx + String.length "/__test-viewer") path

    else
        path


{-| Extract the test name from the URL path after the base path.
e.g., "/__test-viewer/FrameworkTests.counterClicksTest" -> Just "FrameworkTests.counterClicksTest"
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

                    testName =
                        model.tests |> List.drop newIndex |> List.head |> Maybe.map .name
                in
                ( { model
                    | currentTestIndex = newIndex
                    , currentStepIndex = 0
                    , hoveredStepIndex = Nothing
                    , expandedGroups = Set.empty
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

                    testName =
                        model.tests |> List.drop newIndex |> List.head |> Maybe.map .name
                in
                ( { model
                    | currentTestIndex = newIndex
                    , currentStepIndex = 0
                    , hoveredStepIndex = Nothing
                    , expandedGroups = Set.empty
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
            in
            ( { model
                | currentTestIndex = clampedIndex
                , currentStepIndex = stepIndex
                , hoveredStepIndex = Nothing
                , sidebarMode = CommandLog
                , expandedGroups = Set.empty
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

        ToggleEffects ->
            ( { model | showEffects = not model.showEffects }, Cmd.none )

        ToggleNetwork ->
            ( { model | showNetwork = not model.showNetwork }, Cmd.none )

        ToggleFetchers ->
            ( { model | showFetchers = not model.showFetchers }, Cmd.none )

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


stepKindColor : StepKind -> String
stepKindColor kind =
    case kind of
        Start ->
            "#8899aa"

        Interaction ->
            "#4cc9f0"

        Assertion ->
            "#7ee787"

        EffectResolution ->
            "#f0c040"

        Error ->
            "#e74c3c"


stepKindIcon : StepKind -> String
stepKindIcon kind =
    case kind of
        Start ->
            ">"

        Interaction ->
            "~"

        Assertion ->
            "?"

        EffectResolution ->
            "*"

        Error ->
            "!"



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
                    viewNetworkSidebar
                        (displayedSnapshot model
                            |> Maybe.map .networkLog
                            |> Maybe.withDefault []
                        )

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
            (snapshots
                |> List.indexedMap
                    (\i snapshot ->
                        let
                            isChild =
                                isChildStep i snapshots

                            numChildren =
                                childCount i snapshots

                            isGroupParent =
                                not isChild && numChildren > 0

                            isExpanded =
                                Set.member i model.expandedGroups

                            isHiddenChild =
                                isChild && not (Set.member (parentOfChild i snapshots) model.expandedGroups)
                        in
                        if isHiddenChild then
                            Html.text ""

                        else
                            viewStepRow i snapshot model.currentStepIndex isHovering (model.hoveredStepIndex == Just i) (failureCauseIndex == Just i) isChild isGroupParent isExpanded numChildren
                    )
            )
        ]


viewStepRow : Int -> Snapshot -> Int -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Int -> Html Msg
viewStepRow index snapshot currentIndex isHovering isHovered isFailureCause isChild isGroupParent isExpanded numChildren =
    let
        isActive =
            index == currentIndex

        isPast =
            index < currentIndex

        kindColor =
            stepKindColor snapshot.stepKind
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
            [ Html.text (stepKindIcon snapshot.stepKind) ]
        , Html.span [ Attr.class "step-label", Attr.title snapshot.label ]
            (viewStepLabel snapshot)
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

          else if snapshot.hasPendingEffects then
            Html.span [ Attr.class "step-pending-badge" ] [ Html.text "pending" ]

          else
            Html.text ""
        ]


{-| Render a step label with structured formatting for assertion steps.
For assertions, the function name is dimmed and the selector detail is highlighted.
For other steps, the label is shown as-is.
-}
viewStepLabel : Snapshot -> List (Html Msg)
viewStepLabel snapshot =
    let
        label =
            snapshot.label
    in
    case snapshot.stepKind of
        Assertion ->
            -- Parse "ensureViewHas text \"Hello\" (within .foo)" into parts
            case splitAssertionLabel label of
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
                    [ Html.text label ]

        _ ->
            [ Html.text label ]


{-| Split an assertion label like "ensureViewHas text \"Hello\" (within .foo)"
into its function name, selector detail, and optional scope.
-}
splitAssertionLabel : String -> Maybe { fnName : String, selectorDetail : String, withinScope : Maybe String }
splitAssertionLabel label =
    let
        prefixes =
            [ "ensureViewHas ", "ensureViewHasNot ", "ensureView" ]

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
                                viewModelInspector
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
                            [ viewUrlBar previewSnapshot
                            , viewRenderedPageWithOptions model.viewportWidth
                                (if hasPrevious && not isStartStep then
                                    Just model.previewMode

                                 else
                                    Nothing
                                )
                                previewSnapshot
                            , if not isStartStep && hasPrevious then
                                viewBeforeAfterToggle model.previewMode

                              else
                                Html.text ""
                            , if model.showFetchers then
                                viewFetcherInspector (displayedStepIndex model) (currentSnapshots model)

                              else
                                Html.text ""
                            , if model.showEffects then
                                viewEffectInspector snapshot

                              else
                                Html.text ""
                            , if model.showModel then
                                viewModelInspector previewSnapshot

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
            , Attr.attribute "src" "/__test-viewer-preview"
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
                        ( Just target, _ ) ->
                            [ Attr.attribute "data-highlight" (Encode.encode 0 (encodeTargetSelector target)) ]

                        ( Nothing, _ :: _ ) ->
                            [ Attr.attribute "data-highlight" (Encode.encode 0 (encodeAssertionHighlight snapshot.assertionSelectors)) ]

                        _ ->
                            []
                   )
            )
            (snapshot.body
                |> List.map (Html.map (\_ -> NoOp))
            )
        , Html.node "iframe"
            ([ Attr.id "preview-iframe"
             , Attr.attribute "src" "/__test-viewer-preview"
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


viewModelInspector : Snapshot -> Html Msg
viewModelInspector snapshot =
    Html.div [ Attr.class "model-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ] [ Html.text "Model" ]
        , Html.pre [ Attr.class "inspector-body" ]
            [ Html.text
                (snapshot.modelState
                    |> Maybe.withDefault "(use withModelToString to enable)"
                )
            ]
        ]


viewFetcherInspector : Int -> List Snapshot -> Html Msg
viewFetcherInspector currentStep allSnapshots =
    let
        -- Collect all unique fetcher IDs across all snapshots
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

        -- For each fetcher, build its timeline: list of (stepIndex, FetcherEntry)
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

        -- Deduplicate consecutive entries with the same status
        dedupeTimeline : List ( Int, FetcherEntry ) -> List ( Int, FetcherEntry )
        dedupeTimeline entries =
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

        statusIcon status =
            case status of
                FetcherSubmitting ->
                    Html.span [ Attr.class "fetcher-status-icon fetcher-submitting" ] [ Html.text "▶" ]

                FetcherReloading ->
                    Html.span [ Attr.class "fetcher-status-icon fetcher-reloading" ] [ Html.text "↻" ]

                FetcherComplete ->
                    Html.span [ Attr.class "fetcher-status-icon fetcher-complete" ] [ Html.text "✓" ]

        statusLabel status =
            case status of
                FetcherSubmitting ->
                    "Submitting"

                FetcherReloading ->
                    "Reloading"

                FetcherComplete ->
                    "Complete"

        viewFetcherCard fetcherId =
            let
                timeline =
                    dedupeTimeline (fetcherTimeline fetcherId)

                firstEntry =
                    timeline |> List.head |> Maybe.map Tuple.second
            in
            Html.div [ Attr.class "fetcher-card" ]
                [ Html.div [ Attr.class "fetcher-card-header" ]
                    [ Html.span [ Attr.class "fetcher-id" ] [ Html.text ("\"" ++ fetcherId ++ "\"") ]
                    , case firstEntry of
                        Just entry ->
                            Html.span [ Attr.class "fetcher-action" ]
                                [ Html.text (entry.method ++ " " ++ entry.action) ]

                        Nothing ->
                            Html.text ""
                    ]
                , Html.div [ Attr.class "fetcher-timeline" ]
                    (timeline
                        |> List.map
                            (\( stepIdx, entry ) ->
                                let
                                    temporal =
                                        if stepIdx == currentStep then
                                            "fetcher-timeline-current"

                                        else if stepIdx < currentStep then
                                            "fetcher-timeline-past"

                                        else
                                            "fetcher-timeline-future"
                                in
                                Html.div
                                    [ Attr.classList
                                        [ ( "fetcher-timeline-entry", True )
                                        , ( temporal, True )
                                        ]
                                    ]
                                    [ Html.span [ Attr.class "fetcher-step" ]
                                        [ Html.text ("Step " ++ String.fromInt (stepIdx + 1)) ]
                                    , statusIcon entry.status
                                    , Html.span [ Attr.class "fetcher-status-label" ]
                                        [ Html.text (statusLabel entry.status) ]
                                    , if entry.status == FetcherSubmitting && not (List.isEmpty entry.fields) then
                                        Html.span [ Attr.class "fetcher-fields" ]
                                            [ Html.text
                                                (entry.fields
                                                    |> List.map (\( k, v ) -> k ++ "=" ++ v)
                                                    |> String.join ", "
                                                )
                                            ]

                                      else
                                        Html.text ""
                                    ]
                            )
                    )
                ]
    in
    Html.div [ Attr.class "fetcher-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ]
            [ Html.text
                ("Fetchers ("
                    ++ String.fromInt (List.length allFetcherIds)
                    ++ ")"
                )
            ]
        , if List.isEmpty allFetcherIds then
            Html.div [ Attr.class "fetcher-empty" ]
                [ Html.text "No fetcher submissions in this test." ]

          else
            Html.div [ Attr.class "fetcher-list" ]
                (allFetcherIds |> List.map viewFetcherCard)
        ]


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



viewNetworkSidebar : List NetworkEntry -> Html Msg
viewNetworkSidebar entries =
    Html.div [ Attr.class "network-sidebar" ]
        [ Html.div [ Attr.class "network-sidebar-header" ]
            [ Html.span [ Attr.class "sidebar-title" ]
                [ Html.text ("Network (" ++ String.fromInt (List.length entries) ++ ")") ]
            ]
        , if List.isEmpty entries then
            Html.div [ Attr.class "network-empty" ]
                [ Html.text "No HTTP requests recorded." ]

          else
            Html.div [ Attr.class "network-list" ]
                (entries
                    |> List.map
                        (\entry ->
                            Html.div
                                [ Attr.classList
                                    [ ( "network-row", True )
                                    , ( "network-row-pending", entry.status == Pending )
                                    ]
                                ]
                                ([ Html.div [ Attr.class "network-row-top" ]
                                    [ case entry.status of
                                        Stubbed ->
                                            Html.span [ Attr.class "net-badge net-badge-stubbed" ]
                                                [ Html.text "stubbed" ]

                                        Pending ->
                                            Html.span [ Attr.class "net-badge net-badge-pending" ]
                                                [ Html.text "pending" ]
                                    , Html.span [ Attr.class "net-method" ]
                                        [ Html.text entry.method ]
                                    , Html.span [ Attr.class "net-step" ]
                                        [ Html.text ("step " ++ String.fromInt (entry.stepIndex + 1)) ]
                                    ]
                                 , Html.div [ Attr.class "net-url", Attr.title entry.url ]
                                    [ Html.text
                                        (case entry.portName of
                                            Just name ->
                                                name

                                            Nothing ->
                                                entry.url
                                        )
                                    ]
                                 ]
                                    ++ (case entry.responsePreview of
                                            Just preview ->
                                                [ Html.details [ Attr.class "net-response-details" ]
                                                    [ Html.summary [ Attr.class "net-response-summary" ]
                                                        [ Html.text "Response" ]
                                                    , Html.pre [ Attr.class "net-response-body" ]
                                                        [ Html.text (truncatePreview 500 preview) ]
                                                    ]
                                                ]

                                            Nothing ->
                                                []
                                       )
                                )
                        )
                )
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
            encodeAssertionHighlight selectors


encodeAssertionHighlight : List AssertionSelector -> Encode.Value
encodeAssertionHighlight selectors =
    Encode.object
        [ ( "type", Encode.string "assertion" )
        , ( "selectors", Encode.list encodeAssertionSelector selectors )
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
                s.stepKind == Assertion

            Nothing ->
                False


{-| Find the parent step index for a child step (the nearest preceding
non-child step).
-}
parentOfChild : Int -> List Snapshot -> Int
parentOfChild i snapshots =
    if i <= 0 then
        0

    else if not (isChildStep i snapshots) then
        i

    else
        parentOfChild (i - 1) snapshots


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

    else
        prev


{-| Count the number of consecutive child (assertion) steps following a
given parent index.
-}
childCount : Int -> List Snapshot -> Int
childCount parentIndex snapshots =
    snapshots
        |> List.drop (parentIndex + 1)
        |> List.foldl
            (\s ( count, continue ) ->
                if continue && s.stepKind == Assertion then
                    ( count + 1, True )

                else
                    ( count, False )
            )
            ( 0, True )
        |> Tuple.first



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

.step-row-failure-cause {
    border-left-color: #e74c3c;
    background: rgba(231, 76, 60, 0.05);
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
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    font-weight: 700;
    min-width: 14px;
    text-align: center;
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

.step-pending-badge {
    font-size: 9px;
    color: #f0c040;
    background: rgba(240, 192, 64, 0.15);
    padding: 1px 5px;
    border-radius: 3px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
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

/* === NETWORK SIDEBAR === */

.network-sidebar {
    width: 300px;
    min-width: 300px;
    display: flex;
    flex-direction: column;
    background: #16213e;
    border-left: 1px solid #0f3460;
    overflow: hidden;
}

.network-sidebar-header {
    padding: 10px 12px 8px;
    border-bottom: 1px solid #0f3460;
}

.network-empty {
    padding: 12px;
    color: #556677;
    font-size: 12px;
    font-style: italic;
}

.network-list {
    flex: 1;
    overflow-y: auto;
    padding: 4px 0;
}

.network-row {
    padding: 6px 12px;
    border-bottom: 1px solid rgba(15, 52, 96, 0.3);
    transition: background 0.08s;
}

.network-row:hover {
    background: rgba(76, 201, 240, 0.05);
}

.network-row-pending {
    opacity: 0.7;
}

.network-row-top {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 2px;
}

.net-method {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    color: #4cc9f0;
    font-weight: 600;
}

.net-url {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 11px;
    color: #8899aa;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.net-step {
    font-size: 10px;
    color: #556677;
    margin-left: auto;
}

.net-badge {
    font-size: 9px;
    padding: 1px 6px;
    border-radius: 3px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
    font-weight: 600;
    flex-shrink: 0;
}

.net-badge-stubbed {
    background: rgba(42, 110, 78, 0.3);
    color: #7ee787;
}

.net-badge-pending {
    background: rgba(240, 192, 64, 0.15);
    color: #f0c040;
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

/* === BEFORE/AFTER TOGGLE === */

.before-after-toggle {
    display: flex;
    justify-content: center;
    gap: 2px;
    padding: 6px 0;
    flex-shrink: 0;
}

.ba-btn {
    padding: 4px 14px;
    border: 1px solid #0f3460;
    background: #16213e;
    color: #8899aa;
    font-size: 12px;
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

/* === EFFECT INSPECTOR === */

/* === FETCHER INSPECTOR === */

.fetcher-inspector {
    flex-shrink: 0;
    max-height: 240px;
    overflow: auto;
    background: #0d1117;
    border-top: 1px solid #0f3460;
    margin: 0 12px;
    border-radius: 6px 6px 0 0;
}

.fetcher-empty {
    padding: 8px 12px 12px;
    color: #556677;
    font-size: 12px;
    font-style: italic;
}

.fetcher-list {
    padding: 4px 0 8px;
}

.fetcher-card {
    padding: 4px 12px 8px;
}

.fetcher-card + .fetcher-card {
    border-top: 1px solid rgba(255,255,255,0.05);
    margin-top: 4px;
    padding-top: 8px;
}

.fetcher-card-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 4px;
}

.fetcher-id {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    color: #a855f7;
    font-weight: 600;
}

.fetcher-action {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 11px;
    color: #556677;
}

.fetcher-timeline {
    padding-left: 8px;
    border-left: 2px solid rgba(255,255,255,0.06);
}

.fetcher-timeline-entry {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 0 2px 8px;
    font-size: 12px;
    opacity: 0.6;
}

.fetcher-timeline-entry.fetcher-timeline-past {
    opacity: 0.35;
}

.fetcher-timeline-entry.fetcher-timeline-current {
    opacity: 1;
    background: rgba(168, 85, 247, 0.12);
    border-radius: 3px;
    margin-left: -2px;
    padding-left: 10px;
    font-weight: 600;
}

.fetcher-timeline-entry.fetcher-timeline-future {
    opacity: 0.4;
    border-left: 2px dashed rgba(255,255,255,0.1);
    margin-left: -2px;
    padding-left: 6px;
}

.fetcher-step {
    color: #556677;
    font-size: 11px;
    min-width: 48px;
}

.fetcher-status-icon {
    font-size: 11px;
}

.fetcher-submitting {
    color: #f0c040;
}

.fetcher-reloading {
    color: #4cc9f0;
}

.fetcher-complete {
    color: #7ee787;
}

.fetcher-status-label {
    color: #8899aa;
    font-size: 12px;
}

.fetcher-fields {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 11px;
    color: #556677;
    margin-left: 4px;
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
    max-height: 200px;
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
    color: #7ee787;
    white-space: pre-wrap;
    word-break: break-all;
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
