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
import Html.Keyed as Keyed
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
                  , showModel = True
                  , sidebarMode = initialMode
                  , navKey = key
                  , basePath = basePath
                  , searchQuery = ""
                  , viewportWidth = Nothing
                  , showEffects = True
                  , showNetwork = True
                  , showNetworkBackend = True
                  , showNetworkFrontend = True
                  , showFetchers = True
                  , showCookies = True
                  , previewMode = After
                  , expandedGroups = defaultExpandedGroups initialSnapshots
                  , modelTreeExpanded = Set.empty
                  }
                , focusSidebar
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


{-| Refocus the steps rail container. Without this the iframe preview
can grab focus (autofocused inputs, programmatic `Browser.Dom.focus`
calls inside the rendered app) and steal arrow-key keyboard navigation
— `Browser.Events.onKeyDown` listens on the parent window and never
sees keydowns once focus has moved into the iframe document.
-}
focusSidebar : Cmd Msg
focusSidebar =
    Browser.Dom.focus "sidebar-steps"
        |> Task.attempt (\_ -> NoOp)


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
            , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex, focusSidebar ]
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
                            , Cmd.batch [ scrollToStep parentIdx, focusSidebar ]
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
                        , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex, focusSidebar ]
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
                        , Cmd.batch [ scrollToStep newIndex, syncStepToUrl newModel newIndex, focusSidebar ]
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


{-| Highest 1-indexed step number that's currently visible in the rail
(excludes hidden children of collapsed groups + collapsed named groups).
The header counter uses this so its denominator matches the row label
the user sees at the bottom of the rail, not the raw snapshot count.
-}
lastVisibleStepNumber : List Snapshot -> Set Int -> Int
lastVisibleStepNumber snapshots expandedGroups =
    let
        isHiddenAt i =
            let
                child =
                    isChildStep i snapshots
            in
            (child && not (Set.member (parentOfChild i snapshots) expandedGroups))
                || isHiddenByNamedGroup i snapshots expandedGroups
    in
    snapshots
        |> List.indexedMap (\i _ -> i)
        |> List.filter (\i -> not (isHiddenAt i))
        |> List.reverse
        |> List.head
        |> Maybe.map (\i -> i + 1)
        |> Maybe.withDefault (List.length snapshots)


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


{-| Split a `Module.Name.testName` style identifier into its module path
and the test function name. Used by the suite overview to group tests
under their owning module.
-}
splitTestName : String -> { module_ : String, name : String }
splitTestName fullName =
    case String.split "." fullName |> List.reverse of
        last :: revRest ->
            { module_ = revRest |> List.reverse |> String.join "."
            , name = last
            }

        [] ->
            { module_ = "", name = fullName }


{-| Group tests by their module name, preserving each test's original
index in the test list (so click-to-open still navigates correctly).
Groups appear in first-encounter order; tests within a group preserve
declaration order with failing tests bubbled to the top.
-}
groupTestsByModule : List NamedTest -> List ( String, List ( Int, NamedTest ) )
groupTestsByModule tests =
    let
        ordered =
            tests
                |> List.indexedMap Tuple.pair
                |> List.foldl
                    (\( idx, t ) acc ->
                        let
                            mod =
                                (splitTestName t.name).module_
                        in
                        case List.partition (\( m, _ ) -> m == mod) acc of
                            ( [ ( _, existing ) ], rest ) ->
                                rest ++ [ ( mod, existing ++ [ ( idx, t ) ] ) ]

                            _ ->
                                acc ++ [ ( mod, [ ( idx, t ) ] ) ]
                    )
                    []
    in
    ordered
        |> List.map
            (\( mod, members ) ->
                ( mod
                , members
                    |> List.sortBy
                        (\( _, t ) ->
                            if testHasError t then
                                0

                            else
                                1
                        )
                )
            )


{-| Locate the snapshot that triggered a test failure. Returns the
1-indexed step number plus the error message if found.
-}
firstErrorAt : NamedTest -> Maybe { atStep : Int, errorMsg : String }
firstErrorAt test =
    test.snapshots
        |> List.indexedMap Tuple.pair
        |> List.filterMap
            (\( i, s ) ->
                case ( s.stepKind, s.errorMessage ) of
                    ( Error, Just msg ) ->
                        Just { atStep = i + 1, errorMsg = msg }

                    _ ->
                        Nothing
            )
        |> List.head


-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "elm-pages Test Viewer"
    , body =
        [ Html.node "style" [] [ Html.text css ]
        , Html.div [ Attr.class "viewer" ]
            (case model.sidebarMode of
                TestList ->
                    viewSuiteOverview model

                CommandLog ->
                    viewCommandLogShell model
            )
        ]
    }


viewSuiteOverview : Model -> List (Html Msg)
viewSuiteOverview model =
    [ viewHeader model
    , Html.div [ Attr.class "viewer-body suite-overview-body" ]
        [ viewTestListSidebar model
        , viewSuiteMain model
        ]
    ]


viewCommandLogShell : Model -> List (Html Msg)
viewCommandLogShell model =
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
                    Html.div [ Attr.class "header-center-row" ]
                        [ Html.span [ Attr.class "test-name" ]
                            [ Html.text (currentTestName model) ]
                        , viewStepCounter model
                        ]
            ]
        , Html.div [ Attr.class "header-right" ]
            [ viewViewportPicker model.viewportWidth
            , viewChannelToggle
                { on = model.showNetwork
                , msg = ToggleNetwork
                , label = "Network"
                , icon = Icons.eventNetworkSized
                }
            , viewChannelToggle
                { on = model.showFetchers
                , msg = ToggleFetchers
                , label = "Fetchers"
                , icon = Icons.eventFetcherSized
                }
            , viewChannelToggle
                { on = model.showCookies
                , msg = ToggleCookies
                , label = "Cookies"
                , icon = Icons.eventCookieSized
                }
            , viewChannelToggle
                { on = model.showEffects
                , msg = ToggleEffects
                , label = "Effects"
                , icon = Icons.eventEffectSized
                }
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


{-| A header toggle with a channel glyph + label. The glyph takes the
button's own active / inactive color (not the channel color) so the
toolbar reads as a uniform strip; the channel color lives on the rail
dots and panel headers instead.
-}
viewChannelToggle :
    { on : Bool
    , msg : Msg
    , label : String
    , icon : Int -> String -> Html Msg
    }
    -> Html Msg
viewChannelToggle cfg =
    let
        iconColor =
            if cfg.on then
                "#4cc9f0"

            else
                "#556677"
    in
    Html.button
        [ Attr.classList
            [ ( "toggle-button", True )
            , ( "toggle-active", cfg.on )
            ]
        , Html.Events.onClick cfg.msg
        ]
        [ cfg.icon 14 iconColor
        , Html.text cfg.label
        ]


{-| Step counter pill — the most important piece of state in the viewer,
so give it a real anchor. Soft cyan wash pill with the current step
number rendered bold and bright (channel-cyan, matching the steps-rail
current-step indicator).
-}
viewStepCounter : Model -> Html Msg
viewStepCounter model =
    let
        position =
            model.currentStepIndex + 1

        lastVisible =
            lastVisibleStepNumber (currentSnapshots model) model.expandedGroups

        -- If the user has somehow landed on a hidden step (e.g. via a
        -- permalink into a collapsed group), keep the denominator >= the
        -- numerator so the counter never reads `21 / 18`.
        total =
            max position lastVisible
    in
    Html.span [ Attr.class "step-counter" ]
        [ Html.span [ Attr.class "step-counter-label" ] [ Html.text "Step" ]
        , Html.span [ Attr.class "step-counter-current" ]
            [ Html.text (String.fromInt position) ]
        , Html.span [ Attr.class "step-counter-total" ]
            [ Html.text ("/ " ++ String.fromInt total) ]
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
        q =
            String.toLower model.searchQuery

        matchesFilter t =
            String.isEmpty q || String.contains q (String.toLower t.name)

        filteredGroups =
            groupTestsByModule model.tests
                |> List.filterMap
                    (\( mod, members ) ->
                        case List.filter (\( _, t ) -> matchesFilter t) members of
                            [] ->
                                Nothing

                            kept ->
                                Just ( mod, kept )
                    )

        totalTests =
            List.length model.tests
    in
    Html.aside [ Attr.class "suite-sidebar" ]
        [ Html.div [ Attr.class "suite-sidebar-header" ]
            [ Html.div [ Attr.class "suite-sidebar-title" ]
                [ Html.text (String.fromInt totalTests ++ " tests") ]
            , Html.input
                [ Attr.class "suite-filter-input"
                , Attr.placeholder "Filter tests…"
                , Attr.value model.searchQuery
                , Html.Events.onInput UpdateSearch
                ]
                []
            ]
        , Html.div [ Attr.class "suite-sidebar-list" ]
            (if List.isEmpty filteredGroups then
                [ Html.div [ Attr.class "suite-sidebar-empty" ]
                    [ Html.text "No tests match" ]
                ]

             else
                filteredGroups |> List.map (viewSuiteSidebarGroup model)
            )
        ]


viewSuiteSidebarGroup : Model -> ( String, List ( Int, NamedTest ) ) -> Html Msg
viewSuiteSidebarGroup model ( mod, members ) =
    let
        total =
            List.length members

        failing =
            members |> List.filter (\( _, t ) -> testHasError t) |> List.length

        statusBadge =
            if failing > 0 then
                Html.span [ Attr.class "suite-group-count suite-group-count-failing" ]
                    [ Html.text ("✗ " ++ String.fromInt failing ++ " / " ++ String.fromInt total) ]

            else
                Html.span [ Attr.class "suite-group-count suite-group-count-passing" ]
                    [ Html.text ("✓ " ++ String.fromInt total) ]
    in
    Html.div [ Attr.class "suite-group" ]
        [ Html.div [ Attr.class "suite-group-header" ]
            [ Html.span [ Attr.class "suite-group-name" ] [ Html.text mod ]
            , statusBadge
            ]
        , Html.div [ Attr.class "suite-group-tests" ]
            (members |> List.map (viewSuiteSidebarTestRow model))
        ]


viewSuiteSidebarTestRow : Model -> ( Int, NamedTest ) -> Html Msg
viewSuiteSidebarTestRow model ( idx, test ) =
    let
        hasError =
            testHasError test

        stepCount =
            List.length test.snapshots

        nameOnly =
            (splitTestName test.name).name

        meta =
            case firstErrorAt test of
                Just { atStep } ->
                    Html.span [ Attr.class "suite-test-meta" ]
                        [ Html.text (String.fromInt stepCount ++ " steps")
                        , Html.span [ Attr.class "suite-test-meta-failure" ]
                            [ Html.text (" · failed at " ++ String.fromInt atStep) ]
                        ]

                Nothing ->
                    Html.span [ Attr.class "suite-test-meta" ]
                        [ Html.text (String.fromInt stepCount ++ " steps") ]

        statusGlyph =
            if hasError then
                Html.span [ Attr.class "suite-test-status suite-test-status-fail" ] [ Html.text "✗" ]

            else
                Html.span [ Attr.class "suite-test-status suite-test-status-pass" ] [ Html.text "✓" ]
    in
    Html.button
        [ Attr.classList
            [ ( "suite-test-row", True )
            , ( "suite-test-row-fail", hasError )
            ]
        , Html.Events.onClick (GoToTest idx)
        ]
        [ statusGlyph
        , Html.div [ Attr.class "suite-test-body" ]
            [ Html.div [ Attr.class "suite-test-name" ] [ Html.text nameOnly ]
            , meta
            ]
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
        , Html.div
            [ Attr.class "sidebar-steps"
            , Attr.id "sidebar-steps"
            , Attr.tabindex 0
            ]
            (viewRailColumnHeader model
                :: (let
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
                                            viewStepChannelGutter model events
                                    in
                                    [ viewStepRow i snapshot model.currentStepIndex isHovering (model.hoveredStepIndex == Just i) (failureCauseIndex == Just i) isChild isGroupParent isExpanded numChildren eventDots ]
                        in
                        groupHeader ++ stepRow
                    )
                   )
            )
        , viewStepDrawer model
        ]


{-| Pass-8 step detail drawer. Lives at the bottom of the rail and
renders content-sized detail for the currently displayed step. MVP
covers two step kinds: assertions (Selector + Expected) and
navigations (Kind + URL). Every other step kind returns an empty
node — the drawer simply doesn't appear.
-}
viewStepDrawer : Model -> Html Msg
viewStepDrawer model =
    let
        snapshots =
            currentSnapshots model

        stepIndex =
            displayedStepIndex model
    in
    case snapshots |> List.drop stepIndex |> List.head of
        Just snapshot ->
            case snapshot.stepKind of
                Assertion ->
                    viewAssertionDrawer stepIndex snapshot

                Interaction ->
                    if isNavigationLabel snapshot.label then
                        viewNavigationDrawer stepIndex snapshot

                    else
                        Html.text ""

                _ ->
                    Html.text ""

        Nothing ->
            Html.text ""


isNavigationLabel : String -> Bool
isNavigationLabel label =
    String.startsWith "navigateTo " label
        || String.startsWith "redirected" label


viewAssertionDrawer : Int -> Snapshot -> Html Msg
viewAssertionDrawer stepIndex snapshot =
    let
        kindBadge =
            assertionKindBadge snapshot.assertionSelectors

        scopeSelector =
            -- Innermost scope is the element the assertion targets.
            -- A bare `ensureViewHas` (no `withinFind`) has empty scope
            -- and we omit the Selector row entirely.
            snapshot.scopeSelectors
                |> List.reverse
                |> List.head
                |> Maybe.map formatSelectors
                |> Maybe.andThen
                    (\s ->
                        if String.isEmpty s then
                            Nothing

                        else
                            Just s
                    )

        expected =
            assertionExpected snapshot.assertionSelectors
    in
    Html.div [ Attr.class "step-detail-drawer step-detail-drawer-assertion" ]
        [ Html.div [ Attr.class "drawer-header drawer-header-assertion" ]
            [ Html.span [ Attr.class "drawer-header-step" ]
                [ Html.text ("Step " ++ String.fromInt (stepIndex + 1)) ]
            , Html.span [ Attr.class "drawer-header-sep" ] [ Html.text "·" ]
            , Html.span [ Attr.class "drawer-header-kind" ] [ Html.text "Assertion" ]
            , case kindBadge of
                Just badge ->
                    Html.span [ Attr.class "drawer-header-sep" ] [ Html.text "·" ]

                Nothing ->
                    Html.text ""
            , case kindBadge of
                Just badge ->
                    Html.span [ Attr.class "drawer-header-subkind" ] [ Html.text badge ]

                Nothing ->
                    Html.text ""
            ]
        , Html.div [ Attr.class "drawer-body" ]
            ((case scopeSelector of
                Just sel ->
                    [ drawerRow "Selector" "step-arg-class" sel ]

                Nothing ->
                    []
             )
                ++ (case expected of
                        Just ( valueClass, valueText ) ->
                            [ drawerRow "Expected" valueClass valueText ]

                        Nothing ->
                            []
                   )
            )
        ]


viewNavigationDrawer : Int -> Snapshot -> Html Msg
viewNavigationDrawer stepIndex snapshot =
    let
        ( kind, url ) =
            parseNavigationLabel snapshot.label
    in
    Html.div [ Attr.class "step-detail-drawer step-detail-drawer-navigation" ]
        [ Html.div [ Attr.class "drawer-header drawer-header-navigation" ]
            [ Html.span [ Attr.class "drawer-header-step" ]
                [ Html.text ("Step " ++ String.fromInt (stepIndex + 1)) ]
            , Html.span [ Attr.class "drawer-header-sep" ] [ Html.text "·" ]
            , Html.span [ Attr.class "drawer-header-kind" ] [ Html.text "Navigation" ]
            ]
        , Html.div [ Attr.class "drawer-body" ]
            [ drawerRow "Kind" "step-arg-custom" kind
            , drawerRow "URL" "step-arg-url" url
            ]
        ]


drawerRow : String -> String -> String -> Html Msg
drawerRow label valueClass value =
    Html.div [ Attr.class "drawer-row" ]
        [ Html.span [ Attr.class "drawer-label" ] [ Html.text label ]
        , Html.span [ Attr.class ("drawer-value " ++ valueClass) ] [ Html.text value ]
        ]


{-| Best-effort badge for the assertion's first selector so the header
reads `Step N · Assertion · TEXT` (or CLASS / ATTR / etc.).
-}
assertionKindBadge : List AssertionSelector -> Maybe String
assertionKindBadge selectors =
    case List.head selectors of
        Just (ByText _) ->
            Just "Text"

        Just (ByClass _) ->
            Just "Class"

        Just (ById_ _) ->
            Just "Id"

        Just (ByTag_ _) ->
            Just "Tag"

        Just (ByValue _) ->
            Just "Value"

        Just (ByContaining _) ->
            Just "Containing"

        _ ->
            Nothing


{-| Pull the expected value + a class describing how to color it. The
class names match the rail's argument colors so the drawer and rail
agree on what each kind looks like. -}
assertionExpected : List AssertionSelector -> Maybe ( String, String )
assertionExpected selectors =
    case List.head selectors of
        Just (ByText s) ->
            Just ( "step-arg-text", "\"" ++ s ++ "\"" )

        Just (ByClass s) ->
            Just ( "step-arg-class", "." ++ s )

        Just (ById_ s) ->
            Just ( "step-arg-attr", "#" ++ s )

        Just (ByTag_ s) ->
            Just ( "step-arg-empty", s )

        Just (ByValue s) ->
            Just ( "step-arg-attr", "[value=\"" ++ s ++ "\"]" )

        Just (ByContaining inner) ->
            Just ( "step-arg-empty", formatSelectors inner )

        Just (ByOther s) ->
            Just ( "step-arg-empty", s )

        Nothing ->
            Nothing


{-| Render a list of `AssertionSelector` as a single CSS-like string,
e.g. `[ByTag_ "ul", ById_ "todo-list"]` → `ul#todo-list`.
-}
formatSelectors : List AssertionSelector -> String
formatSelectors selectors =
    selectors |> List.map formatOneSelector |> String.concat


formatOneSelector : AssertionSelector -> String
formatOneSelector selector =
    case selector of
        ByTag_ s ->
            s

        ByClass s ->
            "." ++ s

        ById_ s ->
            "#" ++ s

        ByText s ->
            ":contains(\"" ++ s ++ "\")"

        ByValue s ->
            "[value=\"" ++ s ++ "\"]"

        ByContaining inner ->
            ":has(" ++ formatSelectors inner ++ ")"

        ByOther s ->
            s


parseNavigationLabel : String -> ( String, String )
parseNavigationLabel label =
    if String.startsWith "navigateTo " label then
        -- `navigateTo` represents the test landing at a URL — clicking
        -- a magic link, browser-bar paste, etc. The framework treats
        -- this exactly like a server-issued redirect (fresh data load
        -- on the new path, route resolution from scratch) so it reads
        -- as "Redirect" to a test author scanning the step list.
        ( "Redirect", stripOuterQuotes (String.dropLeft 11 label) )

    else if String.startsWith "redirected→" label then
        ( "Redirect", stripOuterQuotes (String.dropLeft 11 label) )

    else if String.startsWith "redirected " label then
        ( "Redirect", stripOuterQuotes (String.dropLeft 11 label) )

    else
        ( "Navigate", label )


viewRailColumnHeader : Model -> Html Msg
viewRailColumnHeader model =
    let
        cell : Bool -> String -> Html Msg -> Html Msg
        cell visible color glyph =
            Html.span
                [ Attr.class "step-channel-cell"
                , Attr.style "color"
                    (if visible then
                        color

                     else
                        "#3a4555"
                    )
                ]
                [ glyph ]
    in
    Html.div [ Attr.class "rail-column-header" ]
        [ Html.span [ Attr.class "step-channel-gutter rail-column-header-gutter" ]
            [ cell model.showFetchers Icons.channelColorFetcher (Icons.eventFetcher Icons.channelColorFetcher)
            , cell (model.showNetworkBackend || model.showNetworkFrontend) Icons.channelColorNetworkBackend (Icons.eventNetwork Icons.channelColorNetworkBackend)
            , cell model.showCookies Icons.channelColorCookie (Icons.eventCookie Icons.channelColorCookie)
            , cell model.showEffects Icons.channelColorEffect (Icons.eventEffect Icons.channelColorEffect)
            ]
        ]


viewStepRow : Int -> Snapshot -> Int -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Int -> Html Msg -> Html Msg
viewStepRow index snapshot currentIndex isHovering isHovered isFailureCause isChild isGroupParent isExpanded numChildren eventDots =
    let
        isActive =
            index == currentIndex

        isPast =
            index < currentIndex
    in
    Html.div
        [ Attr.classList
            [ ( "step-row", True )
            , ( "step-row-active", isActive )
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
        , Html.span [ Attr.class "step-icon" ]
            [ Icons.verbIconForSnapshot snapshot ]
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


{-| Render the right-edge channel gutter — 4 fixed cells in F/N/C/E order.
Each cell is 14px square. Populated cells render the channel glyph + an
optional count badge; empty cells render a 2px dim dot so the eye can scan
down a single column. Hidden channels (toolbar toggle off) render as empty.
-}
viewStepChannelGutter : Model -> StepEvents -> Html Msg
viewStepChannelGutter model events =
    let
        networkVisible =
            model.showNetworkBackend || model.showNetworkFrontend

        networkCount =
            (if model.showNetworkBackend then
                events.networkBackend

             else
                0
            )
                + (if model.showNetworkFrontend then
                    events.networkFrontend

                   else
                    0
                  )
    in
    Html.span [ Attr.class "step-channel-gutter" ]
        [ channelCell model.showFetchers events.fetcher Icons.channelColorFetcher (Icons.eventFetcher Icons.channelColorFetcher) "fetcher"
        , channelCell networkVisible networkCount Icons.channelColorNetworkBackend (Icons.eventNetwork Icons.channelColorNetworkBackend) "network"
        , channelCell model.showCookies events.cookie Icons.channelColorCookie (Icons.eventCookie Icons.channelColorCookie) "cookie"
        , channelCell model.showEffects events.effect Icons.channelColorEffect (Icons.eventEffect Icons.channelColorEffect) "effect"
        ]


channelCell : Bool -> Int -> String -> Html msg -> String -> Html msg
channelCell visible count color glyph titleWord =
    if not visible || count <= 0 then
        Html.span [ Attr.class "step-channel-cell step-channel-cell-empty" ]
            [ Html.span [ Attr.class "step-channel-empty-dot" ] [] ]

    else
        Html.span
            [ Attr.class "step-channel-cell"
            , Attr.title (String.fromInt count ++ " " ++ titleWord ++ " event")
            , Attr.style "color" color
            ]
            [ glyph
            , if count > 1 then
                Html.span [ Attr.class "step-channel-count" ]
                    [ Html.text (String.fromInt count) ]

              else
                Html.text ""
            ]


{-| The kind of argument a step takes — drives sigils + color in the rail.
-}
type ArgKind
    = ArgClass
    | ArgText
    | ArgAttr
    | ArgCustom
    | ArgUrl
    | ArgEmpty


{-| Result of `splitAssertionLabel` — the arg kind drives rendering.
The `argValue` has surrounding quotes stripped; the `withinScope` has the
outer `(within ...)` wrapper stripped (the inner selector remains).
-}
type alias SplitLabel =
    { fnName : String
    , argKind : ArgKind
    , argValue : String
    , withinScope : Maybe String
    }


{-| Render a step label with structured formatting using arg-kind sigils.
For any step whose label starts with a recognized verb, the verb word is
gone (replaced upstream by the verb icon) and the argument carries the
visual weight via per-kind sigils + colors.
-}
viewStepLabel : Snapshot -> List (Html Msg)
viewStepLabel snapshot =
    case splitAssertionLabel snapshot.label of
        Just split ->
            viewArgCell split
                ++ (case split.withinScope of
                        Just scope ->
                            [ Html.span [ Attr.class "step-label-scope" ]
                                [ Html.text ("\u{00A0}in " ++ scope) ]
                            ]

                        Nothing ->
                            []
                   )

        Nothing ->
            [ Html.text snapshot.label ]


viewArgCell : SplitLabel -> List (Html Msg)
viewArgCell split =
    case split.argKind of
        ArgClass ->
            [ Html.span [ Attr.class "step-arg step-arg-class" ]
                [ Html.text ("." ++ split.argValue) ]
            ]

        ArgText ->
            [ Html.span [ Attr.class "step-arg-quote" ] [ Html.text "\"" ]
            , Html.span [ Attr.class "step-arg step-arg-text" ] [ Html.text split.argValue ]
            , Html.span [ Attr.class "step-arg-quote" ] [ Html.text "\"" ]
            ]

        ArgAttr ->
            [ Html.span [ Attr.class "step-arg step-arg-attr" ]
                [ Html.text ("[" ++ split.argValue ++ "]") ]
            ]

        ArgCustom ->
            [ Html.span [ Attr.class "step-arg step-arg-custom" ]
                [ Html.text split.argValue ]
            ]

        ArgUrl ->
            [ Html.span [ Attr.class "step-arg step-arg-url" ]
                [ Html.text split.argValue ]
            ]

        ArgEmpty ->
            [ Html.span [ Attr.class "step-arg step-arg-empty" ]
                [ Html.text split.argValue ]
            ]


{-| Split a step label into verb + arg-kind + cleaned arg value, honoring an
optional trailing `(within ...)` scope. Recognizes assertion prefixes as well
as the common interaction / setup / navigation verbs.
-}
splitAssertionLabel : String -> Maybe SplitLabel
splitAssertionLabel label =
    let
        -- (prefix, default arg kind for this verb)
        prefixes : List ( String, ArgKind )
        prefixes =
            [ ( "ensureViewHas ", ArgEmpty )
            , ( "ensureViewHasNot ", ArgEmpty )
            , ( "ensureView", ArgEmpty )
            , ( "ensureBrowserUrl ", ArgUrl )
            , ( "expectViewHas ", ArgEmpty )
            , ( "expectViewHasNot ", ArgEmpty )
            , ( "clickButtonWith ", ArgClass )
            , ( "clickButton ", ArgText )
            , ( "clickLinkByText ", ArgText )
            , ( "clickLinkWith ", ArgClass )
            , ( "clickLink ", ArgText )
            , ( "selectOption ", ArgText )
            , ( "check ", ArgText )
            , ( "uncheck ", ArgText )
            , ( "fillIn ", ArgText )
            , ( "fillInTextarea ", ArgText )
            , ( "simulateHttpPost ", ArgUrl )
            , ( "simulateHttpGet ", ArgUrl )
            , ( "simulateCustom ", ArgCustom )
            , ( "simulateCommand ", ArgCustom )
            , ( "navigateTo ", ArgUrl )
            , ( "redirected ", ArgUrl )
            , ( "redirected→", ArgUrl )
            ]

        tryPrefix ( prefix, defaultKind ) =
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

                    ( argKind, argValue ) =
                        inferArgKind defaultKind selectorPart
                in
                Just
                    { fnName = String.trimRight prefix
                    , argKind = argKind
                    , argValue = argValue
                    , withinScope = scopePart
                    }

            else
                Nothing
    in
    firstJust tryPrefix prefixes


{-| Refine a default arg kind by inspecting the selector detail. Recognizes
the inner-selector forms (`text "..."`, `class "..."`, `attribute "..."`)
that show up after `ensureViewHas`-family verbs, and strips outer quotes
from simple quoted args.

`attribute "name" "value"` is a *two-arg* form — render as `name="value"`
(brackets are added by the renderer) so it reads like a CSS attribute
selector instead of `[name" "value]` from naïve outer-quote stripping.
-}
inferArgKind : ArgKind -> String -> ( ArgKind, String )
inferArgKind defaultKind detail =
    let
        trimmed =
            String.trim detail
    in
    if String.startsWith "text " trimmed then
        ( ArgText, stripOuterQuotes (String.dropLeft 5 trimmed) )

    else if String.startsWith "exact text " trimmed then
        ( ArgText, stripOuterQuotes (String.dropLeft 11 trimmed) )

    else if String.startsWith "class " trimmed then
        ( ArgClass, stripOuterQuotes (String.dropLeft 6 trimmed) )

    else if String.startsWith "attribute " trimmed then
        case extractQuotedArgs (String.dropLeft 10 trimmed) of
            [ name, value ] ->
                ( ArgAttr, name ++ "=\"" ++ value ++ "\"" )

            [ name ] ->
                ( ArgAttr, name )

            _ ->
                ( ArgAttr, stripOuterQuotes trimmed )

    else if String.startsWith "id " trimmed then
        ( ArgAttr, stripOuterQuotes (String.dropLeft 3 trimmed) )

    else
        ( defaultKind, stripOuterQuotes trimmed )


{-| Pull every `"..."` chunk out of a string, in order. Used to parse
multi-arg selector forms like `attribute "value" "Write tests"` into
`["value", "Write tests"]`.
-}
extractQuotedArgs : String -> List String
extractQuotedArgs s =
    let
        helper : List String -> String -> List String
        helper acc remaining =
            let
                trimmed =
                    String.trimLeft remaining
            in
            if String.startsWith "\"" trimmed then
                let
                    body =
                        String.dropLeft 1 trimmed
                in
                case String.indices "\"" body of
                    i :: _ ->
                        helper (String.left i body :: acc) (String.dropLeft (i + 1) body)

                    [] ->
                        List.reverse acc

            else
                List.reverse acc
    in
    helper [] s


{-| Drop a single pair of outer double-quotes if present.
-}
stripOuterQuotes : String -> String
stripOuterQuotes s =
    let
        t =
            String.trim s
    in
    if String.startsWith "\"" t && String.endsWith "\"" t && String.length t >= 2 then
        String.slice 1 (String.length t - 1) t

    else
        t


{-| Extract "(within ...)" suffix from a label string.
Returns (selector part, scope inner) if found, with the outer `(within ` /
`)` wrapper stripped from the scope.
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
            let
                rawScope =
                    String.dropLeft (idx + String.length marker) str

                inner =
                    if String.endsWith ")" rawScope then
                        String.dropRight 1 rawScope

                    else
                        rawScope
            in
            Just
                ( String.left idx str
                , inner
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


{-| Right-area content for the suite overview. Renders the calm
PassingCard when every test is green, or a stack of FailureCards
when any test fails. Empty suite (no tests) gets its own card.
-}
viewSuiteMain : Model -> Html Msg
viewSuiteMain model =
    let
        failingTests =
            model.tests
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, t ) -> testHasError t)

        passingCount =
            List.length model.tests - List.length failingTests
    in
    Html.div [ Attr.class "suite-main" ]
        [ if List.isEmpty model.tests then
            viewSuiteEmptyCard

          else if List.isEmpty failingTests then
            viewPassingCard passingCount

          else
            viewFailureReport failingTests model
        ]


viewSuiteEmptyCard : Html Msg
viewSuiteEmptyCard =
    Html.div [ Attr.class "suite-card suite-card-empty" ]
        [ Html.div [ Attr.class "suite-card-body-text" ]
            [ Html.text "No tests yet. Add a test to your suite to see it here." ]
        ]


viewPassingCard : Int -> Html Msg
viewPassingCard count =
    Html.div [ Attr.class "suite-card suite-card-passing" ]
        [ Html.div [ Attr.class "suite-card-badge" ]
            [ Html.span [ Attr.class "suite-card-check" ] [ Html.text "✓" ] ]
        , Html.h2 [ Attr.class "suite-card-heading" ]
            [ Html.text (String.fromInt count ++ " tests passing") ]
        , Html.p [ Attr.class "suite-card-body-text" ]
            [ Html.text "Suite is healthy. Pick any test on the left to step through it." ]
        ]


viewFailureReport : List ( Int, NamedTest ) -> Model -> Html Msg
viewFailureReport failingTests _ =
    let
        n =
            List.length failingTests
    in
    Html.div [ Attr.class "suite-failure-report" ]
        [ Html.div [ Attr.class "suite-failure-strip" ]
            [ Html.text ("Failure report · " ++ String.fromInt n ++ " failing") ]
        , Html.div [ Attr.class "suite-failure-stack" ]
            (failingTests |> List.map viewFailureCard)
        ]


viewFailureCard : ( Int, NamedTest ) -> Html Msg
viewFailureCard ( idx, test ) =
    let
        split =
            splitTestName test.name

        totalSteps =
            List.length test.snapshots

        atInfo =
            firstErrorAt test
    in
    Html.div [ Attr.class "suite-failure-card" ]
        [ Html.div [ Attr.class "suite-failure-card-header" ]
            [ Html.span [ Attr.class "suite-failure-x" ] [ Html.text "✗" ]
            , Html.div [ Attr.class "suite-failure-card-title-block" ]
                [ Html.div [ Attr.class "suite-failure-card-title" ]
                    [ Html.span [ Attr.class "suite-failure-card-module" ]
                        [ Html.text (split.module_ ++ ".") ]
                    , Html.span [ Attr.class "suite-failure-card-name" ]
                        [ Html.text split.name ]
                    ]
                , case atInfo of
                    Just { atStep } ->
                        Html.div [ Attr.class "suite-failure-card-at-step" ]
                            [ Html.text
                                ("failed at step "
                                    ++ String.fromInt atStep
                                    ++ " of "
                                    ++ String.fromInt totalSteps
                                )
                            ]

                    Nothing ->
                        Html.text ""
                ]
            , Html.button
                [ Attr.class "suite-failure-card-open"
                , Html.Events.onClick (GoToTest idx)
                ]
                [ Html.text "Open test →" ]
            ]
        , case atInfo of
            Just { errorMsg } ->
                Html.div [ Attr.class "suite-failure-card-body" ]
                    [ Html.div [ Attr.class "suite-failure-row" ]
                        [ Html.span [ Attr.class "suite-failure-label" ] [ Html.text "Error" ]
                        , Html.pre [ Attr.class "suite-failure-value suite-failure-value-actual" ]
                            [ Html.text errorMsg ]
                        ]
                    ]

            Nothing ->
                Html.text ""
        ]


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
                                    (displayedStepIndex model)
                                    previousSnapshot
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
                                                -- Render prev's body, but show the *current* step's
                                                -- target / scope / assertions so the highlight points
                                                -- at what's about to be clicked or asserted on.
                                                -- Without copying scopeSelectors, a scoped click like
                                                -- `withinFind [li containing "Write tests"] (clickButtonWith class "destroy")`
                                                -- would lose its scope in Before mode and either fail
                                                -- to highlight or point at the wrong destroy button.
                                                { prev
                                                    | targetElement = snapshot.targetElement
                                                    , scopeSelectors = snapshot.scopeSelectors
                                                    , assertionSelectors = snapshot.assertionSelectors
                                                }

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
                                viewModelInspector model.modelTreeExpanded
                                    (displayedStepIndex model)
                                    previousSnapshot
                                    previewSnapshot

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
            , Html.span [ Attr.class "page-title-text" ] [ Html.text snapshot.title ]
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


{-| Pass-11: render the user-side model with a diff against the previous
step's snapshot. Changed lines get a persistent mark + a one-shot flash
on every step transition.

The flash is keyed off `stepIndex` — the inspector body is wrapped in a
keyed div whose `Html.Keyed` key includes the step number, so each step
change remounts the body and restarts the CSS animation on each marked
line.
-}
viewModelInspector : Set String -> Int -> Maybe Snapshot -> Snapshot -> Html Msg
viewModelInspector expandedNodes stepIndex previousSnapshot snapshot =
    Html.div [ Attr.class "model-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ] [ Html.text "Model" ]
        , Keyed.node "div"
            [ Attr.class "inspector-body" ]
            [ ( "model-step-" ++ String.fromInt stepIndex
              , viewModelInspectorBody expandedNodes previousSnapshot snapshot
              )
            ]
        ]


viewModelInspectorBody : Set String -> Maybe Snapshot -> Snapshot -> Html Msg
viewModelInspectorBody expandedNodes previousSnapshot snapshot =
    case snapshot.modelState of
        Nothing ->
            Html.span [ Attr.class "dv-internals" ]
                [ Html.text "(use withModelInspector to enable)" ]

        Just modelStr ->
            case DebugParser.parse modelStr of
                Ok value ->
                    let
                        diffs =
                            case previousSnapshot |> Maybe.andThen .modelState of
                                Just prevStr ->
                                    case DebugParser.parse prevStr of
                                        Ok prevValue ->
                                            DebugParser.diff prevValue value

                                        Err _ ->
                                            Dict.empty

                                Nothing ->
                                    Dict.empty

                        -- Auto-expand the path to every changed line so the
                        -- user actually sees the marks while scrolling. The
                        -- user's manual expanded set is kept separate; the
                        -- two are unioned at render time. Collapsing a node
                        -- that has a change inside it will spring back open
                        -- on the next step transition (auto-expand wins),
                        -- but that's the right call — the diff is the most
                        -- relevant signal at the moment of transition.
                        autoExpanded =
                            autoExpandedFromDiffs diffs

                        effectiveExpanded =
                            Set.union expandedNodes autoExpanded
                    in
                    DebugParser.viewValue
                        { expanded = effectiveExpanded
                        , onToggle = ToggleModelNode
                        , diffs = diffs
                        }
                        "root"
                        value

                Err _ ->
                    Html.div []
                        [ Html.div [ Attr.class "model-parse-error-banner" ]
                            [ Html.text "DebugParser couldn't parse this snapshot — falling back to raw text. Copy the contents below and share them so the parser can be patched." ]
                        , Html.pre [ Attr.class "model-parse-error-raw" ] [ Html.text modelStr ]
                        ]


{-| For every changed path in the diff, emit the path itself and all
of its ancestors. Without this the user would only see the change
mark if the containing record / list / variant was already expanded
in their session.

E.g. a change at `root.app.data.entries.0.completed` returns
`{root, root.app, root.app.data, root.app.data.entries,
root.app.data.entries.0, root.app.data.entries.0.completed}`. The
leaf path is harmless — leaves don't render a toggle anyway.
-}
autoExpandedFromDiffs : Dict String DebugParser.DiffKind -> Set String
autoExpandedFromDiffs diffs =
    diffs
        |> Dict.keys
        |> List.concatMap pathAndAncestors
        |> Set.fromList


pathAndAncestors : String -> List String
pathAndAncestors path =
    let
        parts =
            String.split "." path
    in
    List.range 1 (List.length parts)
        |> List.map (\n -> parts |> List.take n |> String.join ".")


{-| Icon-event chip vocabulary shared by the Network and Fetcher panels.
Each `EventKind` determines the glyph and color; `active` flips the chip
from outlined to filled-pill (the "current state" treatment); `future`
dims the chip to hint at "hasn't happened yet".
-}
type EventKind
    = EventSubmit
    | EventReload
    | EventComplete
    | EventFail
    | EventSent


eventKindColor : EventKind -> String
eventKindColor kind =
    case kind of
        EventSubmit ->
            "#86efac"

        EventReload ->
            "#fcd34d"

        EventComplete ->
            "#7dd3fc"

        EventFail ->
            "#fca5a5"

        EventSent ->
            "#86efac"


eventKindClass : EventKind -> String
eventKindClass kind =
    case kind of
        EventSubmit ->
            "event-chip-kind-submit"

        EventReload ->
            "event-chip-kind-reload"

        EventComplete ->
            "event-chip-kind-complete"

        EventFail ->
            "event-chip-kind-fail"

        EventSent ->
            "event-chip-kind-sent"


eventKindGlyph : EventKind -> (Int -> String -> Html msg)
eventKindGlyph kind =
    case kind of
        EventSubmit ->
            Icons.eventUp

        EventReload ->
            Icons.eventDown

        EventComplete ->
            Icons.eventCheck

        EventFail ->
            Icons.eventCross

        EventSent ->
            Icons.eventUpRight


{-| A single icon + step-number pill. The chip is a `<button>` that
navigates to the event's step on click. `active` (filled-pill) and
`future` (dimmed outline) are mutually exclusive in practice.
-}
viewEventChip :
    { step : Int
    , kind : EventKind
    , active : Bool
    , future : Bool
    , currentStepHere : Bool
    }
    -> Html Msg
viewEventChip cfg =
    let
        chip =
            Html.button
                [ Attr.classList
                    [ ( "event-chip", True )
                    , ( eventKindClass cfg.kind, True )
                    , ( "event-chip-active", cfg.active )
                    , ( "event-chip-now", cfg.currentStepHere )
                    , ( "event-chip-future", cfg.future )
                    ]
                , Html.Events.onClick (GoToStep cfg.step)
                ]
                [ eventKindGlyph cfg.kind 11 "currentColor"
                , Html.text (String.fromInt (cfg.step + 1))
                ]
    in
    if cfg.currentStepHere then
        withCurrentStepRing "#7dd3fc" chip

    else
        chip


{-| Wrap any inline element in the shared "this is the current step"
ring + glow halo. The shell is `position: relative` and `display:
inline-flex`, the ring is absolutely positioned at `inset: -2px`, so
the wrapped element's layout box (and the surrounding row's height /
alignment) is unchanged whether or not the ring is present.

Used by both the event-chip timeline (Network + Fetcher panels) and
the cookie box-pill selector. Color is supplied per call so each
context can tie the ring to the right channel/state color.

-}
withCurrentStepRing : String -> Html msg -> Html msg
withCurrentStepRing color inner =
    Html.span [ Attr.class "current-step-shell" ]
        [ inner
        , Html.span
            [ Attr.class "current-step-ring"
            , Attr.style "--ring-color" color
            ]
            []
        ]


{-| Thin 8×1 line linking two event chips. Color follows the destination
chip's state — past chips get a translucent slice of their own color,
future chips get a muted neutral. No arrow glyph.
-}
viewEventChipConnector : { kind : EventKind, future : Bool } -> Html Msg
viewEventChipConnector cfg =
    Html.span
        [ Attr.classList
            [ ( "event-chip-connector", True )
            , ( eventKindClass cfg.kind, True )
            , ( "event-chip-connector-future", cfg.future )
            ]
        ]
        []


{-| Render a list of event chips joined by connectors. Each connector
adopts the destination chip's kind + future flag.
-}
viewEventChipRow :
    List
        { step : Int
        , kind : EventKind
        , active : Bool
        , future : Bool
        , currentStepHere : Bool
        }
    -> List (Html Msg)
viewEventChipRow entries =
    entries
        |> List.indexedMap
            (\i e ->
                if i == 0 then
                    [ viewEventChip e ]

                else
                    [ viewEventChipConnector { kind = e.kind, future = e.future }
                    , viewEventChip e
                    ]
            )
        |> List.concat


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

        statusToEventKind : FetcherStatus -> EventKind
        statusToEventKind status =
            case status of
                FetcherSubmitting ->
                    EventSubmit

                FetcherReloading ->
                    EventReload

                FetcherComplete ->
                    EventComplete

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

                submitFields : List ( String, String )
                submitFields =
                    timeline
                        |> List.filter (\( _, e ) -> e.status == FetcherSubmitting)
                        |> List.head
                        |> Maybe.map (Tuple.second >> .fields)
                        |> Maybe.withDefault []

                pulseColor =
                    case currentEntry of
                        Just ( _, entry ) ->
                            eventKindColor (statusToEventKind entry.status)

                        Nothing ->
                            "#86efac"

                chipEntries =
                    timeline
                        |> List.map
                            (\( stepIdx, entry ) ->
                                { step = stepIdx
                                , kind = statusToEventKind entry.status
                                , active =
                                    case currentEntry of
                                        Just ( activeIdx, _ ) ->
                                            stepIdx == activeIdx

                                        Nothing ->
                                            False
                                , future = stepIdx > currentStep
                                , currentStepHere = stepIdx == currentStep
                                }
                            )
            in
            Html.div
                [ Attr.classList
                    [ ( "fetcher-card", True )
                    , ( "fetcher-card-live", isLive )
                    ]
                , Attr.style "--pulse-color" pulseColor
                ]
                [ Html.div [ Attr.class "fetcher-card-header" ]
                    [ case firstEntry of
                        Just entry ->
                            Html.span [ Attr.class "net-method net-method-http" ]
                                [ Html.text entry.method ]

                        Nothing ->
                            Html.text ""
                    , Html.span [ Attr.class "fetcher-id" ] [ Html.text ("\"" ++ fetcherId ++ "\"") ]
                    ]
                , Html.div [ Attr.class "event-chip-row" ]
                    (viewEventChipRow chipEntries)
                , if List.isEmpty submitFields then
                    Html.text ""

                  else
                    Html.div [ Attr.class "fetcher-fields" ]
                        (submitFields
                            |> List.indexedMap
                                (\i ( k, v ) ->
                                    Html.span [ Attr.class "fetcher-field" ]
                                        [ if i == 0 then
                                            Html.text ""

                                          else
                                            Html.span [ Attr.class "fetcher-field-sep" ]
                                                [ Html.text " · " ]
                                        , Html.span [ Attr.class "fetcher-field-key" ]
                                            [ Html.text k ]
                                        , Html.text " "
                                        , Html.span [ Attr.class "fetcher-field-value" ]
                                            [ Html.text v ]
                                        ]
                                )
                        )
                ]
    in
    Html.div [ Attr.class "fetcher-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ]
            [ Icons.eventFetcherSized 20 Icons.channelColorFetcher
            , Html.span [ Attr.class "sidebar-title" ]
                [ Html.text "Fetchers" ]
            ]
        , if List.isEmpty allFetcherIds then
            Html.div [ Attr.class "fetcher-empty" ]
                [ Html.div [ Attr.class "channel-empty-icon" ]
                    [ Icons.eventFetcherSized 48 Icons.channelColorFetcher ]
                , Html.text "No fetcher submissions in this test."
                ]

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
            [ Icons.eventEffectSized 20 Icons.channelColorEffect
            , Html.span [ Attr.class "sidebar-title" ]
                [ Html.text "Effects" ]
            , Html.span [ Attr.class "sidebar-subtitle" ]
                [ Html.text (String.fromInt (List.length snapshot.pendingEffects) ++ " pending") ]
            ]
        , if List.isEmpty snapshot.pendingEffects then
            Html.div [ Attr.class "effect-empty" ]
                [ Html.div [ Attr.class "channel-empty-icon" ]
                    [ Icons.eventEffectSized 48 Icons.channelColorEffect ]
                , Html.text "No pending effects at this step."
                ]

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


{-| Build one lane per network request by walking the cumulative snapshot
logs.

Caveat about `entry.stepIndex`: the runtime *overwrites* this field when
a request resolves (see `resolveBackendTask` in `Test.PagesProgram` —
`{ entry | status = Stubbed, stepIndex = List.length state.snapshots }`),
so in later snapshots it reports the *resolution* step, not the creation
step. We therefore can't use `stepIndex` alone as an identity or as
`startStep`.

Instead we lean on the fact that `networkLog` is append-only:

  - Each entry keeps the same **position** in the log across snapshots,
    even when mutated. So position is a stable identity for a request.
  - `startStep` for position `p` = the first snapshot whose log is long
    enough to contain `p`.
  - `endStep` for position `p` = the first snapshot whose log has
    `log[p].status == Stubbed`.

The authoritative list of requests is the final snapshot's log (it's
cumulative, so nothing is missing).

-}
buildNetworkLanes : List Snapshot -> List NetworkLane
buildNetworkLanes allSnapshots =
    let
        indexedSnapshots : List ( Int, Snapshot )
        indexedSnapshots =
            List.indexedMap Tuple.pair allSnapshots

        entryAt : Int -> Snapshot -> Maybe NetworkEntry
        entryAt p snap =
            snap.networkLog |> List.drop p |> List.head

        startStepAt : Int -> Maybe Int
        startStepAt p =
            indexedSnapshots
                |> List.filterMap
                    (\( i, snap ) ->
                        if List.length snap.networkLog > p then
                            Just i

                        else
                            Nothing
                    )
                |> List.head

        endStepAt : Int -> Maybe Int
        endStepAt p =
            indexedSnapshots
                |> List.filterMap
                    (\( i, snap ) ->
                        entryAt p snap
                            |> Maybe.andThen
                                (\e ->
                                    if e.status == Stubbed then
                                        Just i

                                    else
                                        Nothing
                                )
                    )
                |> List.head

        finalLog : List NetworkEntry
        finalLog =
            allSnapshots
                |> List.reverse
                |> List.head
                |> Maybe.map .networkLog
                |> Maybe.withDefault []
    in
    finalLog
        |> List.indexedMap
            (\p entry ->
                { entry = entry
                , startStep = startStepAt p |> Maybe.withDefault entry.stepIndex
                , endStep = endStepAt p
                }
            )


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
    in
    Html.div [ Attr.class "network-sidebar" ]
        [ Html.div [ Attr.class "network-sidebar-header" ]
            [ Html.div [ Attr.class "network-sidebar-title-row" ]
                [ Icons.eventNetworkSized 20 Icons.channelColorNetworkBackend
                , Html.span [ Attr.class "sidebar-title" ]
                    [ Html.text "Network" ]
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
                [ Html.div [ Attr.class "channel-empty-icon" ]
                    [ Icons.eventNetworkSized 48 Icons.channelColorNetworkBackend ]
                , Html.text
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
        isFuture =
            currentStep < lane.startStep

        endReached =
            case lane.endStep of
                Just e ->
                    currentStep >= e

                Nothing ->
                    False

        -- sent but not yet resolved (or no endStep at all)
        isLive =
            not isFuture && not endReached

        startActive =
            isLive

        endActive =
            endReached

        -- `NetworkStatus = Stubbed | Pending` in the current data model, so
        -- we can't distinguish errored from successful responses. Treat all
        -- resolutions as EventComplete until the runtime grows a failed
        -- variant.
        endKind : EventKind
        endKind =
            EventComplete

        stateClass =
            if isFuture then
                "net-row-future"

            else if isLive then
                "net-row-inflight"

            else
                "net-row-resolved"

        isPort =
            lane.entry.portName /= Nothing

        methodClass =
            if isPort then
                "net-method-port"

            else
                case String.toUpper lane.entry.method of
                    "POST" ->
                        "net-method-post"

                    "PUT" ->
                        "net-method-put"

                    "PATCH" ->
                        "net-method-put"

                    "DELETE" ->
                        "net-method-delete"

                    _ ->
                        "net-method-get"

        pathLabel =
            case lane.entry.portName of
                Just name ->
                    name

                Nothing ->
                    lane.entry.url

        hasDetails =
            not (List.isEmpty (userFacingHeaders lane.entry.requestHeaders))
                || lane.entry.requestBody
                /= Nothing
                || lane.entry.responsePreview
                /= Nothing

        pulseColor =
            if isLive then
                eventKindColor EventSent

            else
                "#86efac"

        startChip =
            viewEventChip
                { step = lane.startStep
                , kind = EventSent
                , active = startActive
                , future = isFuture
                , currentStepHere = lane.startStep == currentStep
                }

        -- Network is a two-event model: `sent` + `resolved`. In-flight is
        -- the gap between them, not a third event. We render the sent chip
        -- as active while we're waiting, then flip the end chip to active
        -- once it lands. No "live tail" chip — the filled ↗ says it all.
        chipRow =
            case lane.endStep of
                Just end ->
                    [ startChip
                    , viewEventChipConnector
                        { kind = endKind
                        , future = isFuture || not endReached
                        }
                    , viewEventChip
                        { step = end
                        , kind = endKind
                        , active = endActive
                        , future = isFuture || not endReached
                        , currentStepHere = end == currentStep
                        }
                    ]

                Nothing ->
                    [ startChip ]

        summaryContent =
            [ Html.div [ Attr.class "net-row-head" ]
                [ Html.span [ Attr.class ("net-method " ++ methodClass) ]
                    [ Html.text lane.entry.method ]
                , Html.span [ Attr.class "net-row-path", Attr.title lane.entry.url ]
                    [ Html.text pathLabel ]
                ]
            , Html.div [ Attr.class "event-chip-row" ] chipRow
            ]
    in
    -- Outer wrapper is *always* an `Html.div` (never `Html.details`) so
    -- the row's mount is stable across snapshots. If we conditionally
    -- swapped div ↔ details when `hasDetails` flips (e.g. a response
    -- arrives mid-test), Elm's vdom diff would replace the DOM node
    -- and restart its `::before` animation — knocking the in-flight
    -- pulse out of phase with sibling rows. Disclosure goes on an
    -- inner `Html.details` whose mount is allowed to change freely.
    Html.div
        [ Attr.classList
            [ ( "net-row", True )
            , ( stateClass, True )
            ]
        , Attr.style "--pulse-color" pulseColor
        ]
        (if hasDetails then
            [ Html.details [ Attr.class "net-row-disclose" ]
                (Html.summary [ Attr.class "net-row-summary" ] summaryContent
                    :: [ viewNetRowDetails lane.entry ]
                )
            ]

         else
            [ Html.div [ Attr.class "net-row-summary" ] summaryContent ]
        )


{-| Filter out headers used internally by elm-pages (names starting with
`elm-pages-internal`). They're plumbing, not something the author wrote,
so hiding them keeps the Headers accordion focused on user-visible data.
-}
userFacingHeaders : List ( String, String ) -> List ( String, String )
userFacingHeaders =
    List.filter (\( name, _ ) -> not (String.startsWith "elm-pages-internal" name))


viewNetRowDetails : NetworkEntry -> Html Msg
viewNetRowDetails entry =
    let
        visibleHeaders =
            userFacingHeaders entry.requestHeaders
    in
    Html.div [ Attr.class "net-row-details" ]
        (List.filterMap identity
            [ if List.isEmpty visibleHeaders then
                Nothing

              else
                Just
                    (Html.details [ Attr.class "net-response-details" ]
                        [ Html.summary [ Attr.class "net-response-summary net-headers-summary" ]
                            [ Html.text ("Headers (" ++ String.fromInt (List.length visibleHeaders) ++ ")") ]
                        , Html.div [ Attr.class "net-headers-list" ]
                            (visibleHeaders
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
            [ Icons.eventCookieSized 20 Icons.channelColorCookie
            , Html.span [ Attr.class "sidebar-title" ]
                [ Html.text "Cookies" ]
            ]
        , if List.isEmpty allNames then
            Html.div [ Attr.class "cookie-empty" ]
                [ Html.div [ Attr.class "channel-empty-icon" ]
                    [ Icons.eventCookieSized 48 Icons.channelColorCookie ]
                , Html.text "No cookies set by this test."
                ]

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
            ]
        , if eventCount > 0 then
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
                        ([ Html.summary [ Attr.class "cookie-details-summary" ]
                            [ Html.text "Attributes + raw value" ]
                         ]
                            ++ (case signed of
                                    Just { secret } ->
                                        [ Html.div [ Attr.class "cookie-secret-label" ]
                                            [ Html.text "signed with "
                                            , Html.code [] [ Html.text ("\"" ++ secret ++ "\"") ]
                                            , Html.span [ Attr.class "cookie-fnv-note" ]
                                                [ Html.text "fnv1a (dev)" ]
                                            ]
                                        ]

                                    Nothing ->
                                        []
                               )
                            ++ [ viewCookieAttrTable entry
                               , Html.pre [ Attr.class "cookie-raw-value" ]
                                    [ Html.text entry.value ]
                               ]
                        )

                Nothing ->
                    Html.text ""

          else
            Html.text ""
        ]


{-| C3 "box-pills" step selector. One pill per value-change event; left border
in the cookie channel's tonal range. The pill whose step equals the current
viewer step gets the shared current-step ring halo (`withCurrentStepRing`)
so this panel uses the same "you are here" visual as the Network and Fetcher
event chips. Clicking a pill jumps the viewer to that change point.
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
                                    "cookie-box-pill-kind-set"

                                CookieUpdated _ ->
                                    "cookie-box-pill-kind-changed"

                                CookieRemoved ->
                                    "cookie-box-pill-kind-removed"

                        isActive =
                            currentEventIdx == Just idx

                        isNow =
                            evStep == currentStep

                        pill =
                            Html.button
                                [ Attr.classList
                                    [ ( "cookie-box-pill", True )
                                    , ( kindClass, True )
                                    , ( "cookie-box-pill-active", isActive )
                                    , ( "cookie-box-pill-now", isNow )
                                    ]
                                , Html.Events.onClick (GoToStep evStep)
                                ]
                                [ Html.span [ Attr.class "cookie-box-pill-step" ]
                                    [ Html.text (String.fromInt (evStep + 1)) ]
                                ]

                        wrappedPill =
                            if isNow then
                                withCurrentStepRing "#7dd3fc" pill

                            else
                                pill
                    in
                    if idx == 0 then
                        [ wrappedPill ]

                    else
                        [ Html.span [ Attr.class "event-chip-connector" ] []
                        , wrappedPill
                        ]
                )
            |> List.concat
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
    -- The kind + step that any title would have communicated are
    -- already conveyed by the box-pill row above (kind via the
    -- pill's left-border color, step via the pill number, and the
    -- now-ring marks the current step). Skip the title row and let
    -- the diff body speak for itself.
    let
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
    Html.div [ Attr.class "cookie-diff-card" ] bodyRows


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
            Html.div [ Attr.class "cookie-diff-card cookie-current-card" ] bodyRows


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
    [ viewPayloadSection Nothing Nothing persistentRows
    , viewPayloadSection (Just "FLASH") (Just "ONE-SHOT") flashRows
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
    [ viewPayloadSection Nothing Nothing (asUnchanged persistent)
    , viewPayloadSection (Just "FLASH") (Just "ONE-SHOT") (asUnchanged flashStripped)
    ]


{-| Render one section of a decoded signed-cookie payload. Hidden when
the row list is empty so we don't stamp an empty header.

`title = Nothing` skips the section header entirely — used for the
persistent payload, which is the implicit default. `Just "FLASH"`
renders the section header (with optional ONE-SHOT pill annotation)
to flag that the keys below survive only one read.

-}
viewPayloadSection : Maybe String -> Maybe String -> List ( String, String, KeyDiff ) -> Html Msg
viewPayloadSection maybeTitle pillText rows =
    if List.isEmpty rows then
        Html.text ""

    else
        let
            header =
                case maybeTitle of
                    Just title ->
                        [ Html.div [ Attr.class "cookie-diff-section-header" ]
                            [ Html.span [ Attr.class "cookie-diff-section-title" ] [ Html.text title ]
                            , case pillText of
                                Just t ->
                                    Html.span [ Attr.class "cookie-diff-section-pill" ] [ Html.text t ]

                                Nothing ->
                                    Html.text ""
                            ]
                        ]

                    Nothing ->
                        []
        in
        Html.div [ Attr.class "cookie-diff-section" ]
            (header ++ List.concatMap diffKeyRows rows)


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
viewNamedGroupHeader groupStartIndex name isExpanded _ =
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
    align-items: center;
    overflow-x: auto;
}

.header-center-row {
    display: inline-flex;
    align-items: center;
    gap: 12px;
}

.test-name {
    color: #4cc9f0;
    font-weight: 600;
    font-size: 14px;
}

/* Pass-10 B5: panel-toggle group lives in header-right with 6px gaps;
   the viewport-picker sits adjacent with 4px internal gap and a hairline
   separator to its right (rendered via ::after) so the two groups read
   as visually distinct. */
.header-right {
    display: flex;
    align-items: center;
    gap: 6px;
}

.step-counter {
    display: inline-flex;
    align-items: baseline;
    gap: 6px;
    padding: 4px 10px;
    border-radius: 4px;
    background: rgba(125, 211, 252, 0.08);
    border: 1px solid rgba(125, 211, 252, 0.25);
    font-variant-numeric: tabular-nums;
    font-family: "JetBrains Mono", "SF Mono", monospace;
}

.step-counter-label {
    font-size: 11px;
    font-weight: 500;
    color: #8896a6;
    text-transform: uppercase;
    letter-spacing: 0.05em;
}

.step-counter-current {
    font-size: 14px;
    font-weight: 700;
    color: #7dd3fc;
}

.step-counter-total {
    font-size: 12px;
    color: #a4b1c2;
}

.viewport-picker {
    display: flex;
    gap: 4px;
    margin-right: 16px;
    position: relative;
}

.viewport-picker::after {
    content: "";
    position: absolute;
    right: -8px;
    top: 50%;
    transform: translateY(-50%);
    width: 1px;
    height: 16px;
    background: rgba(255, 255, 255, 0.10);
    pointer-events: none;
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
    display: inline-flex;
    align-items: center;
    gap: 6px;
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
    width: 360px;
    min-width: 360px;
    display: flex;
    flex-direction: column;
    background: #16213e;
    border-right: 1px solid #0f3460;
}

.sidebar-header {
    padding: 12px 14px 10px;
    border-bottom: 1px solid #0f3460;
}

/* Pass-10 A1: panel section headers anchor their panel — secondary
   tier color + weight 700 so they stop reading as ghosted text. */
.sidebar-title {
    font-size: 12px;
    color: #a4b1c2;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 700;
}

.sidebar-steps {
    flex: 1;
    overflow-y: auto;
    padding: 4px 0;
}

/* The steps rail is focusable (`tabindex=0`) so we can refocus it after
   each navigation — that's how arrow-key nav keeps working when the
   iframe preview steals focus. The default focus ring around the whole
   container is noisy; the active step's own treatment already says
   "focus is here." */
.sidebar-steps:focus,
.sidebar-steps:focus-visible {
    outline: none;
}

/* Step detail drawer (pass 8) — content-sized panel at the bottom of
   the rail. `flex-shrink: 0` keeps it at its natural height; an empty
   step kind returns no node at all so the rail body fills the full
   container without dead space. */

.step-detail-drawer {
    flex-shrink: 0;
    border-top: 1px solid rgba(125, 211, 252, 0.18);
    background: #0c121b;
    padding: 8px 12px 12px;
}

.drawer-header {
    display: flex;
    align-items: baseline;
    gap: 6px;
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-size: 11.5px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    margin-bottom: 6px;
}

.drawer-header-step {
    color: #a4b1c2;
}

.drawer-header-sep {
    color: #5c6a7e;
}

.drawer-header-kind {
    color: #c4b5fd;
}

.drawer-header-assertion .drawer-header-kind {
    color: #c4b5fd;
}

.drawer-header-navigation .drawer-header-kind {
    color: #fdba74;
}

.drawer-header-subkind {
    color: #8896a6;
    font-weight: 600;
}

.drawer-body {
    display: grid;
    grid-template-columns: 72px 1fr;
    column-gap: 12px;
    row-gap: 4px;
    align-items: baseline;
}

.drawer-row {
    display: contents;
}

.drawer-label {
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: #a4b1c2;
}

.drawer-value {
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-size: 13.5px;
    font-weight: 500;
    word-break: break-all;
}

/* Fixed-column grid keeps every step row's verb-icon, arg-cell, and
   channel-gutter at the same x-coordinates regardless of label width.
   Columns: [step-number 22px] [verb-icon 18px] [arg cell 1fr]
            [channel-gutter 76px]. The 1fr cell needs `min-width: 0` on
   its child for ellipsis to work — otherwise the label content forces
   the column wider and breaks alignment for every other row. */
.step-row {
    display: grid;
    grid-template-columns: 26px 22px 1fr 88px;
    align-items: center;
    column-gap: 7px;
    padding: 6px 10px 6px 4px;
    cursor: pointer;
    border-left: 2px solid transparent;
    transition: background 0.08s, border-color 0.08s, color 0.08s;
    position: relative;
    line-height: 1.35;
}

.step-row:hover {
    background: rgba(252, 211, 77, 0.10);
    border-left-color: #fcd34d;
}

.step-row-active {
    background: rgba(125, 211, 252, 0.08);
    border-left-color: #7dd3fc;
}

.step-row-active:hover {
    background: rgba(252, 211, 77, 0.10);
    border-left-color: #fcd34d;
}

/* Cross-panel hover synchronization (sets the same warm-yellow as :hover
   when a step is hovered from another panel). */
.step-row-hovered {
    background: rgba(252, 211, 77, 0.10);
    border-left-color: #fcd34d;
}

.step-row-hovered .step-icon,
.step-row-hovered .step-number {
    color: #fcd34d;
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

.step-row-child {
    padding-left: 28px;
    font-size: 13px;
}

.step-row-child .step-number {
    font-size: 12px;
    color: #445566;
}

.step-row-child .step-label {
    font-size: 13px;
    color: #8a9aaa;
}

.step-number {
    font-size: 13px;
    color: #a4b1c2;
    text-align: right;
    font-variant-numeric: tabular-nums;
}

.step-row-active .step-number {
    font-weight: 700;
}

.step-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 18px;
    color: #a4b1c2;
}

.step-icon svg {
    display: block;
    overflow: visible;
}

.step-row:hover .step-icon,
.step-row:hover .step-number {
    color: #fcd34d;
}

.step-row-active .step-icon,
.step-row-active .step-number {
    color: #7dd3fc;
}

.step-row-error .step-icon {
    color: #e74c3c;
}

/* Rail header — sticky at the top of the rail, on the same 4-col grid
   as the step rows so the channel glyphs sit exactly above the gutter
   cells in the data rows below. */

.rail-column-header {
    display: grid;
    grid-template-columns: 26px 22px 1fr 88px;
    align-items: center;
    column-gap: 7px;
    padding: 6px 10px 4px 4px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    margin-bottom: 2px;
    position: sticky;
    top: 0;
    background: #16213e;
    z-index: 1;
    opacity: 0.75;
}

.rail-column-header-gutter {
    grid-column: 4;
    margin-left: 0;
    opacity: 1;
}

/* 4-cell channel-activity gutter, occupying column 4 of the row grid.
   Cells share a fixed x-coordinate so the eye can scan straight down a
   single channel column without horizontal jitter. Empty cells render a
   tiny dim dot rather than collapsing. `justify-content: end` hugs the
   gutter to the right edge of its 76px column. */

.step-channel-gutter {
    display: grid;
    grid-template-columns: repeat(4, 16px);
    column-gap: 4px;
    align-items: center;
    justify-items: center;
    justify-content: end;
    opacity: 0.85;
}

.step-row:hover .step-channel-gutter,
.step-row-active .step-channel-gutter {
    opacity: 1;
}

.step-channel-cell {
    position: relative;
    width: 16px;
    height: 16px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
}

.step-channel-cell svg {
    display: block;
}

/* Empty channel cell — a thin solid dash reads more clearly as
   "column placeholder" than a tiny dot, and the solid #5c6a7e
   (no opacity multiplier) keeps the gutter columns visible as a
   tabular structure even when no row has activity. */
.step-channel-empty-dot {
    width: 5px;
    height: 1.5px;
    border-radius: 0.75px;
    background: #5c6a7e;
}

.step-channel-count {
    position: absolute;
    top: -2px;
    right: -3px;
    font-family: "SF Mono", "JetBrains Mono", "Fira Code", monospace;
    font-size: 10px;
    font-weight: 700;
    line-height: 1;
    color: inherit;
}

.step-label {
    font-size: 13.5px;
    color: #c0c8d0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
}

.step-row-active .step-label {
    color: #e0e8f0;
    font-weight: 500;
}

.step-row-error .step-label {
    color: #e74c3c;
    font-weight: 600;
}

/* Argument cell — kind drives sigil + color. Verb word is gone (replaced
   by the verb-icon column). */

.step-arg {
    font-weight: 500;
}

.step-arg-text { color: #86efac; }
.step-arg-quote { color: #8896a6; font-weight: 400; }
.step-arg-class { color: #c4b5fd; }
.step-arg-attr { color: #fdba74; }
.step-arg-custom { color: #7dd3fc; }
.step-arg-url { color: #fdba74; }
.step-arg-empty { color: #c0c8d0; font-weight: 400; }

.step-row-active .step-arg {
    font-weight: 600;
}

/* The `in <selector>` scope qualifier reads as secondary content but
   it's information, not chrome — bump from #6a7a8a (~3:1) to #a4b1c2
   (~6:1) so it stays comfortably readable next to the arg cell. */
.step-label-scope {
    color: #a4b1c2;
    font-style: italic;
    font-size: 12.5px;
}

/* Failure-cause amber tinge applies to whatever arg color the row uses. */
.step-row-failure-cause .step-arg {
    color: #fcd34d;
}

.model-parse-error-banner {
    padding: 8px 10px;
    margin-bottom: 8px;
    border: 1px solid rgba(252, 165, 165, 0.35);
    background: rgba(252, 165, 165, 0.08);
    color: #fca5a5;
    font-size: 11px;
    line-height: 1.4;
    border-radius: 4px;
}

.model-parse-error-raw {
    background: #0d1117;
    border: 1px solid rgba(255, 255, 255, 0.06);
    border-radius: 4px;
    padding: 10px;
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-size: 11px;
    line-height: 1.5;
    color: #c8d3e0;
    white-space: pre-wrap;
    word-break: break-word;
    max-height: 400px;
    overflow: auto;
    user-select: text;
}

/* === SUITE OVERVIEW === */

.suite-overview-body {
    display: flex;
    flex: 1;
    min-height: 0;
}

.suite-sidebar {
    width: 290px;
    flex-shrink: 0;
    background: #0f1620;
    border-right: 1px solid rgba(255, 255, 255, 0.06);
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.suite-sidebar-header {
    padding: 12px 14px 10px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    flex-shrink: 0;
}

.suite-sidebar-title {
    font-size: 11.5px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #8896a6;
    font-weight: 700;
    margin-bottom: 10px;
}

.suite-filter-input {
    width: 100%;
    padding: 8px 10px;
    background: #0d1117;
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 5px;
    color: #c8d3e0;
    font-size: 13.5px;
    font-family: inherit;
}

.suite-filter-input:focus {
    outline: none;
    border-color: rgba(125, 211, 252, 0.4);
}

.suite-sidebar-list {
    flex: 1;
    overflow-y: auto;
    padding: 4px 0 12px;
}

.suite-sidebar-empty {
    padding: 24px 14px;
    color: #8896a6;
    font-size: 13.5px;
    text-align: center;
}

.suite-group {
    padding: 4px 0;
}

.suite-group-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 8px;
    padding: 12px 14px 6px;
}

.suite-group-name {
    flex: 1;
    font-size: 12.5px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: #a4b1c2;
    white-space: normal;
    word-break: normal;
    line-height: 1.35;
}

.suite-group-count {
    flex-shrink: 0;
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    font-weight: 600;
}

.suite-group-count-passing {
    color: #86efac;
}

.suite-group-count-failing {
    color: #fca5a5;
}

.suite-group-tests {
    padding-left: 14px;
}

.suite-test-row {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    width: 100%;
    padding: 8px 14px 8px 14px;
    background: transparent;
    border: none;
    border-left: 2px solid transparent;
    color: inherit;
    cursor: pointer;
    text-align: left;
    transition: background 0.08s, border-color 0.08s;
}

.suite-test-row:hover {
    background: rgba(125, 211, 252, 0.05);
}

.suite-test-status {
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-weight: 700;
    font-size: 13px;
    margin-top: 3px;
    width: 14px;
    flex-shrink: 0;
}

.suite-test-status-pass {
    color: #86efac;
}

.suite-test-status-fail {
    color: #fca5a5;
}

.suite-test-body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
}

.suite-test-name {
    font-size: 14.5px;
    font-weight: 500;
    color: #c8d3e0;
    word-break: break-word;
    line-height: 1.35;
}

.suite-test-row-fail .suite-test-name {
    color: #fca5a5;
}

.suite-test-meta {
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    color: #8896a6;
}

.suite-test-meta-failure {
    color: #fca5a5;
}

/* === SUITE MAIN (right area) === */

.suite-main {
    flex: 1;
    overflow-y: auto;
    background: #0d1117;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 32px 40px 48px;
    min-width: 0;
}

.suite-card {
    background: #0f1620;
    border: 1px solid rgba(255, 255, 255, 0.06);
    border-radius: 12px;
    padding: 40px 56px;
    max-width: 420px;
    width: 100%;
    text-align: center;
}

.suite-card-passing {
    margin-top: 80px;
}

.suite-card-empty {
    margin-top: 80px;
}

.suite-card-badge {
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: rgba(134, 239, 172, 0.12);
    border: 1px solid rgba(134, 239, 172, 0.30);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 16px;
}

.suite-card-check {
    color: #86efac;
    font-size: 28px;
    font-weight: 700;
    line-height: 1;
}

.suite-card-heading {
    color: #86efac;
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.005em;
    margin-bottom: 12px;
}

.suite-card-body-text {
    color: #a4b1c2;
    font-size: 13px;
    line-height: 1.5;
    max-width: 320px;
    margin: 0 auto;
}

/* Failure report (loud state) */

.suite-failure-report {
    width: 100%;
    max-width: 720px;
}

.suite-failure-strip {
    color: #fca5a5;
    font-size: 9.5px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.10em;
    margin-bottom: 16px;
}

.suite-failure-stack {
    display: flex;
    flex-direction: column;
    gap: 16px;
}

.suite-failure-card {
    background: #0f1620;
    border: 1px solid rgba(252, 165, 165, 0.25);
    border-radius: 10px;
    overflow: hidden;
}

.suite-failure-card-header {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    padding: 14px 18px;
    background: rgba(252, 165, 165, 0.10);
    border-bottom: 1px solid rgba(252, 165, 165, 0.18);
}

.suite-failure-x {
    color: #fca5a5;
    font-size: 14px;
    font-weight: 700;
    margin-top: 2px;
}

.suite-failure-card-title-block {
    flex: 1;
    min-width: 0;
}

.suite-failure-card-title {
    font-size: 14px;
    font-weight: 600;
}

.suite-failure-card-module {
    color: #8896a6;
}

.suite-failure-card-name {
    color: #c8d3e0;
}

.suite-failure-card-at-step {
    margin-top: 4px;
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-size: 11.5px;
    font-variant-numeric: tabular-nums;
    color: #fca5a5;
    font-weight: 500;
}

.suite-failure-card-open {
    flex-shrink: 0;
    background: transparent;
    border: 1px solid rgba(252, 165, 165, 0.35);
    color: #fca5a5;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 6px 12px;
    border-radius: 5px;
    cursor: pointer;
    font-family: inherit;
}

.suite-failure-card-open:hover {
    background: rgba(252, 165, 165, 0.10);
}

.suite-failure-card-body {
    padding: 14px 18px;
    display: grid;
    grid-template-columns: 100px 1fr;
    column-gap: 16px;
    row-gap: 4px;
    align-items: baseline;
}

.suite-failure-row {
    display: contents;
}

.suite-failure-label {
    font-size: 10.5px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: #a4b1c2;
}

.suite-failure-value {
    font-family: "JetBrains Mono", "SF Mono", monospace;
    font-size: 12.5px;
    line-height: 1.5;
    word-break: break-word;
    white-space: pre-wrap;
    margin: 0;
}

.suite-failure-value-actual {
    color: #fca5a5;
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

/* Group-parent rows: when present, the toggle is the 5th child of the
   4-column grid. Position it absolutely so it doesn't wrap onto an
   implicit grid row and break alignment for the row's other cells. */
.step-group-toggle {
    font-size: 10px;
    color: #556677;
    background: rgba(126, 231, 135, 0.1);
    padding: 1px 6px;
    border-radius: 3px;
    cursor: pointer;
    white-space: nowrap;
    position: absolute;
    right: 4px;
    top: 50%;
    transform: translateY(-50%);
}

.step-group-toggle:hover {
    background: rgba(126, 231, 135, 0.2);
    color: #7ee787;
}

/* Named group headers */

/* Section header — same 4-col grid as step rows so the title aligns
   with step labels and the count sits in the channel-gutter column.
   Dimness is baked into the color (#8896a6) rather than stacked on
   top of an opacity multiplier; the bolder font-weight does most of
   the "this is a header" work without forcing extreme dimness. Title
   wraps freely so long section names like "Revisit the login page
   while signed in" stay readable instead of getting clipped. */
.named-group-header {
    display: grid;
    grid-template-columns: 26px 22px 1fr 88px;
    align-items: start;
    column-gap: 8px;
    padding: 16px 12px 8px 5px;
    cursor: pointer;
    background: transparent;
    border-left: 2px solid transparent;
    font-size: 11.5px;
    color: #8896a6;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-weight: 700;
    margin-top: 8px;
    line-height: 1.35;
}

.named-group-header:hover {
    color: #a4b1c2;
}

.named-group-icon {
    grid-column: 1;
    justify-self: end;
    font-size: 8px;
    color: currentColor;
}

.named-group-name {
    grid-column: 2 / 4;
    font-weight: 700;
    color: inherit;
    white-space: normal;
    word-break: normal;
}

.named-group-count {
    grid-column: 4;
    align-self: start;
    flex-shrink: 0;
    text-align: right;
    font-size: 9px;
    font-weight: 600;
    color: #a4b1c2;
    background: transparent;
    padding: 0;
    font-variant-numeric: tabular-nums;
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
    color: #8896a6;
    font-size: 13px;
}

.url-bar-text {
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 13px;
    color: #c8d3e0;
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
    min-width: 0;
    overflow: hidden;
}

/* Ellipsis on the title so a long URL or test name can't shove the
   BEFORE/AFTER badge past the iframe's right edge on narrow viewports.
   The wrapping `.rendered-page` already has `overflow: hidden`, but
   without ellipsis here the badge would just clip mid-character. */
.page-title-text {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
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
    flex-shrink: 0;
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
    padding: 10px 14px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex-shrink: 0;
}

.network-sidebar-title-row {
    display: flex;
    align-items: center;
    gap: 8px;
}

.sidebar-subtitle {
    font-size: 12.5px;
    color: #556677;
    font-variant-numeric: tabular-nums;
    margin-left: 4px;
}

.net-live-count {
    color: #86efac;
    font-weight: 600;
}

.net-filter-buttons {
    display: flex;
    gap: 4px;
    margin-top: 6px;
}

/* Inactive filter pill: outline-only, dim text. Active: solid
   kind-color fill with inverted dark text. The contrast between
   "outline" and "solid-filled" reads from across the room — no
   need for a translucent gradient between the two states. */
/* Pass-10 A3: filter pills follow the canonical pill treatment —
   visible cyan-tinted border (so the pill reads as a button at arm's
   length), secondary-tier text. Active state bumps to solid kind-color
   fill with inverted dark text (handled per-filter below). */
.net-filter-btn {
    font-size: 11.5px;
    padding: 3px 10px;
    border-radius: 11px;
    border: 1px solid rgba(125, 211, 252, 0.25);
    background: transparent;
    color: #a4b1c2;
    cursor: pointer;
    font-family: inherit;
    transition: background 0.08s, color 0.08s, border-color 0.08s;
}

.net-filter-btn:hover {
    color: #e6ecf4;
    border-color: rgba(125, 211, 252, 0.45);
}

.net-filter-backend.net-filter-active {
    background: #f472b6;
    border-color: #f472b6;
    color: #0d1117;
    font-weight: 700;
}

.net-filter-frontend.net-filter-active {
    background: #7dd3fc;
    border-color: #7dd3fc;
    color: #0d1117;
    font-weight: 700;
}

.net-filter-backend.net-filter-active:hover,
.net-filter-frontend.net-filter-active:hover {
    color: #0d1117;
    filter: brightness(1.06);
}

.network-empty,
.cookie-empty,
.fetcher-empty,
.effect-empty {
    padding: 28px 14px 24px;
    color: #5c6a7e;
    font-size: 13.5px;
    font-style: italic;
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
}

.channel-empty-icon {
    opacity: 0.25;
    line-height: 0;
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

/* Inner disclosure wrapper — `Html.details` wraps the summary + body so
   the user can expand the row, but the outer `.net-row` stays a stable
   `Html.div` so its `::before` pulse animation isn't restarted when a
   response arrives mid-test and `hasDetails` flips. */
.net-row-disclose {
    /* transparent passthrough; styles live on summary + details body */
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

/* Future network rows: signaled dim, not flat dim. Three stacked cues
   communicate "this hasn't happened yet" without making the row text
   unreadable — italics carries most of the "tentative" weight, the
   dashed left border anchors the row visually as future, and the
   moderate opacity drop keeps it secondary. Channel glyphs stay at
   full opacity so the rail's structural columns remain crisp. */
.net-row-future {
    opacity: 0.7;
    border-left: 2px dashed rgba(125, 211, 252, 0.4);
    font-style: italic;
}

.net-row-future .step-channel-cell svg,
.net-row-future .event-chip svg {
    opacity: 1;
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

.net-row-inflight::before {
    background: var(--pulse-color, #86efac);
    box-shadow: 0 0 10px var(--pulse-color, rgba(134, 239, 172, 0.8));
}

.net-row-head {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 3px;
}

.net-row-path {
    font-size: 12.5px;
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
    font-size: 10.5px;
    font-weight: 700;
    padding: 1px 5px;
    border-radius: 2px;
    flex-shrink: 0;
    letter-spacing: 0.02em;
}

/* Pass-10 A4: HTTP method tags differentiate by verb so the row reads
   instantly. Each gets a fuller backing tint + tinted border so the
   pill registers at arm's length. */
.net-method-port {
    background: rgba(244, 114, 182, 0.15);
    border: 1px solid rgba(244, 114, 182, 0.30);
    color: #f472b6;
}

.net-method-get,
.net-method-http {
    background: rgba(125, 211, 252, 0.15);
    border: 1px solid rgba(125, 211, 252, 0.30);
    color: #7dd3fc;
}

.net-method-post {
    background: rgba(134, 239, 172, 0.15);
    border: 1px solid rgba(134, 239, 172, 0.30);
    color: #86efac;
}

.net-method-put {
    background: rgba(252, 211, 77, 0.15);
    border: 1px solid rgba(252, 211, 77, 0.30);
    color: #fcd34d;
}

.net-method-delete {
    background: rgba(252, 165, 165, 0.15);
    border: 1px solid rgba(252, 165, 165, 0.30);
    color: #fca5a5;
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
    padding: 10px 14px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    display: flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
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
    font-size: 14.5px;
    font-weight: 600;
    color: #7dd3fc;
}

/* Reads as a discrete pill (fill + border + weight) rather than
   colored text floating in space. Tied to the cookie channel color
   so the visual identity says "this is cookie metadata." */
.cookie-signed-badge {
    font-size: 10.5px;
    font-weight: 700;
    padding: 1px 6px;
    border-radius: 3px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    background: rgba(253, 186, 116, 0.18);
    border: 1px solid rgba(253, 186, 116, 0.35);
    color: #fdba74;
}

.cookie-secret-label {
    font-size: 10px;
    color: #8b99ad;
    margin: 6px 0;
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

/* C3 "box pills" step selector that sits above the stacked value rows.
   Pills are joined by `.event-chip-connector` segments, so the row uses
   align-items: center (to land the connector at the pill mid-line) and
   no inter-element gap (the connector provides the spacing). */
.cookie-pill-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    margin-bottom: 8px;
}

/* Cookie pill kind stripe — amber tonal scale to stay within the
   cookie channel and not borrow from the Network/Fetcher palette. */
.cookie-box-pill-kind-set {
    border-left-color: rgba(252, 211, 77, 0.75);
}

.cookie-box-pill-kind-changed {
    border-left-color: rgba(252, 211, 77, 0.5);
}

.cookie-box-pill-kind-removed {
    border-left-color: rgba(252, 211, 77, 0.25);
}

.cookie-box-pill-step {
    font-variant-numeric: tabular-nums;
}

/* Single diff card per cookie: INITIAL / DIFF / REMOVED panel. */
.cookie-diff-card {
    background: #141a22;
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 5px;
    padding: 10px 12px;
    font-family: "JetBrains Mono", monospace;
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

/* === EVENT CHIP (icon + step-number pill, shared by Network + Fetcher
      panels) === */

.event-chip-row {
    display: flex;
    align-items: center;
    gap: 0;
    margin-left: 22px;
    flex-wrap: wrap;
}

/* Shared base: cookie box-pills (`.cookie-box-pill`) and Network/Fetcher
   event chips (`.event-chip`) use one visual vocabulary so the timeline
   reads the same across panels. Each pill has a 3px kind-colored left
   stripe, neutral 1px borders elsewhere, and gets a cyan-tinted treatment
   when it represents the current state.

   IMPORTANT: do not use the `border:` shorthand here — it resets all four
   border colors at once and would wipe the kind-colored left stripe set
   by `.cookie-box-pill-kind-*` / `.event-chip-kind-*` rules (since those
   rules ship earlier in the stylesheet at equal specificity). Set each
   side explicitly. */
.event-chip,
.cookie-box-pill {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 5px;
    /* Padding + min-width are fixed so flipping the active flag on a
       chip doesn't resize the row, and so paired and unpaired rows share
       a left edge. */
    padding: 3px 7px;
    min-width: 38px;
    box-sizing: border-box;
    border-radius: 3px;
    border-style: solid;
    border-top-width: 1px;
    border-right-width: 1px;
    border-bottom-width: 1px;
    border-left-width: 3px;
    border-top-color: rgba(255, 255, 255, 0.08);
    border-right-color: rgba(255, 255, 255, 0.08);
    border-bottom-color: rgba(255, 255, 255, 0.08);
    background: transparent;
    color: #8b99ad;
    cursor: pointer;
    font-family: "JetBrains Mono", ui-monospace, monospace;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.3;
    font-variant-numeric: tabular-nums;
}

/* Kind classes only paint the left stripe; everything else stays neutral. */
.event-chip-kind-submit { border-left-color: #86efac; }
.event-chip-kind-reload { border-left-color: #fcd34d; }
.event-chip-kind-complete { border-left-color: #7dd3fc; }
.event-chip-kind-fail { border-left-color: #fca5a5; }
.event-chip-kind-sent { border-left-color: #86efac; }

/* Two tiers of "active" state:

   - `active && now` — solid kind-colored background + dark text + soft
     glow. The user is *on* the step that produced this state.
   - `active && !now` — kind-colored outline + soft glow only. The lane
     is in this state right now, but the user has navigated elsewhere.
     Still clearly visible (so you can read each lane's current state at
     a glance) but quieter, so it doesn't compete with the chip the
     user is actually on. */

.event-chip-active:not(.event-chip-now).event-chip-kind-submit,
.event-chip-active:not(.event-chip-now).event-chip-kind-sent {
    border-top-color: #86efac;
    border-right-color: #86efac;
    border-bottom-color: #86efac;
    color: #86efac;
    box-shadow: 0 0 0 1px rgba(134, 239, 172, 0.18), 0 0 6px rgba(134, 239, 172, 0.18);
}

.event-chip-active:not(.event-chip-now).event-chip-kind-reload {
    border-top-color: #fcd34d;
    border-right-color: #fcd34d;
    border-bottom-color: #fcd34d;
    color: #fcd34d;
    box-shadow: 0 0 0 1px rgba(252, 211, 77, 0.18), 0 0 6px rgba(252, 211, 77, 0.18);
}

.event-chip-active:not(.event-chip-now).event-chip-kind-complete {
    border-top-color: #7dd3fc;
    border-right-color: #7dd3fc;
    border-bottom-color: #7dd3fc;
    color: #7dd3fc;
    box-shadow: 0 0 0 1px rgba(125, 211, 252, 0.18), 0 0 6px rgba(125, 211, 252, 0.18);
}

.event-chip-active:not(.event-chip-now).event-chip-kind-fail {
    border-top-color: #fca5a5;
    border-right-color: #fca5a5;
    border-bottom-color: #fca5a5;
    color: #fca5a5;
    box-shadow: 0 0 0 1px rgba(252, 165, 165, 0.18), 0 0 6px rgba(252, 165, 165, 0.18);
}

/* (Active-but-not-now cookie pills used to get per-kind outline +
   colored glow. Pass-10 A2 standardizes: cookie panel step chips
   read as navigational buttons — cyan-tinted border when inactive,
   solid cyan fill when active. Per-kind treatment is gone for the
   navigational chip; the kind-colored 3px left stripe still
   differentiates set/changed/removed.) */

/* Solid kind-colored background + dark text + soft kind-colored glow.
   Only fires when a chip is BOTH the lane's active state AND the
   current step (`-active.-now`) — that's the moment the user is "on"
   the event the chip represents. */
.event-chip-active.event-chip-now {
    color: #0f1620;
    font-weight: 700;
}

.event-chip-active.event-chip-now.event-chip-kind-submit,
.event-chip-active.event-chip-now.event-chip-kind-sent {
    background: #86efac;
    border-top-color: rgba(134, 239, 172, 0.33);
    border-right-color: rgba(134, 239, 172, 0.33);
    border-bottom-color: rgba(134, 239, 172, 0.33);
    box-shadow: 0 0 0 1px rgba(134, 239, 172, 0.33), 0 0 8px rgba(134, 239, 172, 0.2);
}

.event-chip-active.event-chip-now.event-chip-kind-reload {
    background: #fcd34d;
    border-top-color: rgba(252, 211, 77, 0.33);
    border-right-color: rgba(252, 211, 77, 0.33);
    border-bottom-color: rgba(252, 211, 77, 0.33);
    box-shadow: 0 0 0 1px rgba(252, 211, 77, 0.33), 0 0 8px rgba(252, 211, 77, 0.2);
}

.event-chip-active.event-chip-now.event-chip-kind-complete {
    background: #7dd3fc;
    border-top-color: rgba(125, 211, 252, 0.33);
    border-right-color: rgba(125, 211, 252, 0.33);
    border-bottom-color: rgba(125, 211, 252, 0.33);
    box-shadow: 0 0 0 1px rgba(125, 211, 252, 0.33), 0 0 8px rgba(125, 211, 252, 0.2);
}

.event-chip-active.event-chip-now.event-chip-kind-fail {
    background: #fca5a5;
    border-top-color: rgba(252, 165, 165, 0.33);
    border-right-color: rgba(252, 165, 165, 0.33);
    border-bottom-color: rgba(252, 165, 165, 0.33);
    box-shadow: 0 0 0 1px rgba(252, 165, 165, 0.33), 0 0 8px rgba(252, 165, 165, 0.2);
}

/* Pass-10 A2 + B6: cookie pills are navigational chips. Three states:
     - Inactive — cyan-tinted border so the pill reads as a button at
       arm's length, but stays quiet.
     - Active (selected) without now — outline-only with cyan text +
       soft glow. The pill announces "this is the current state" but
       doesn't shout "you are here."
     - Active AND now — solid cyan fill + dark inverted text. Reserved
       for the moment when the selected pill IS the user's current
       step on the rail; that's the only time we go loud. */
.cookie-box-pill {
    border-top-color: rgba(125, 211, 252, 0.25);
    border-right-color: rgba(125, 211, 252, 0.25);
    border-bottom-color: rgba(125, 211, 252, 0.25);
    padding: 4px 10px;
}

.cookie-box-pill-active:not(.cookie-box-pill-now) {
    background: transparent;
    border-top-color: #7dd3fc;
    border-right-color: #7dd3fc;
    border-bottom-color: #7dd3fc;
    color: #7dd3fc;
    font-weight: 700;
    box-shadow: 0 0 0 1px rgba(125, 211, 252, 0.18), 0 0 6px rgba(125, 211, 252, 0.18);
}

.cookie-box-pill-active.cookie-box-pill-now {
    background: #7dd3fc;
    border-top-color: #7dd3fc;
    border-right-color: #7dd3fc;
    border-bottom-color: #7dd3fc;
    color: #0d1117;
    font-weight: 700;
    box-shadow: 0 0 0 1px rgba(125, 211, 252, 0.35), 0 0 8px rgba(125, 211, 252, 0.25);
}

.cookie-box-pill-active.cookie-box-pill-now:hover {
    color: #0d1117;
    filter: brightness(1.06);
}

.cookie-box-pill-active:not(.cookie-box-pill-now):hover {
    color: #b9e9ff;
}

/* Future chips: dimmed-and-muted, kind stripe survives at low alpha. */
.event-chip-future {
    color: #5c6a7e;
    opacity: 0.7;
}

.event-chip:hover,
.cookie-box-pill:hover {
    color: #e6ecf4;
    border-top-color: rgba(255, 255, 255, 0.18);
    border-right-color: rgba(255, 255, 255, 0.18);
    border-bottom-color: rgba(255, 255, 255, 0.18);
}

.event-chip-active.event-chip-now:hover,
.cookie-box-pill-active.cookie-box-pill-now:hover {
    color: #0f1620;
    filter: brightness(1.08);
}

/* Current-step ring halo. Shared by the Network/Fetcher event chips
   and the Cookie box-pill selector — wraps any inline element with a
   thin colored outline that says "this is the step you're on right
   now."

   Implemented as an absolutely-positioned overlay inside a
   zero-padding shell so the wrapped element's bounding box (and
   therefore the surrounding row's layout) is unchanged whether or
   not the ring is present. Color is supplied via the `--ring-color`
   custom property so each caller can tie it to the right kind /
   channel color.

   No blur on the box-shadow: a CSS blur of N pixels paints both
   inward and outward of the shadow's edge, and inward bleed was
   washing out the kind-colored left stripe on cookie box-pills.
   The sharp 1px outline reads clearly on its own. */
.current-step-shell {
    display: inline-flex;
    position: relative;
}

.current-step-ring {
    position: absolute;
    inset: -2px;
    border-radius: 4px;
    box-shadow: 0 0 0 1px var(--ring-color, #7dd3fc);
    pointer-events: none;
}

/* Thin connector between two chips. Takes the destination chip's kind
   color at 50% alpha so the cause→effect thread reads clearly; future
   connectors use a muted white. */
.event-chip-connector {
    width: 8px;
    height: 1px;
    display: inline-block;
    flex-shrink: 0;
    margin: 0 1px;
    background: rgba(255, 255, 255, 0.2);
}

.event-chip-connector.event-chip-kind-submit { background: rgba(134, 239, 172, 0.5); }
.event-chip-connector.event-chip-kind-reload { background: rgba(252, 211, 77, 0.5); }
.event-chip-connector.event-chip-kind-complete { background: rgba(125, 211, 252, 0.5); }
.event-chip-connector.event-chip-kind-fail { background: rgba(252, 165, 165, 0.5); }
.event-chip-connector.event-chip-kind-sent { background: rgba(134, 239, 172, 0.5); }

.event-chip-connector-future {
    background: rgba(255, 255, 255, 0.12);
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

/* Fetcher inspector header inherits the unified .inspector-header
   spec; nothing else to override. */


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

.fetcher-card-live::before {
    background: var(--pulse-color, #86efac);
    box-shadow: 0 0 10px var(--pulse-color, rgba(134, 239, 172, 0.8));
}

.fetcher-card-header {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 6px;
}

.fetcher-id {
    font-family: "JetBrains Mono", monospace;
    font-size: 12.5px;
    color: #e6ecf4;
}

.fetcher-fields {
    font-family: "JetBrains Mono", monospace;
    font-size: 11.5px;
    font-weight: 400;
    margin-top: 4px;
    padding-left: 22px;
}

.fetcher-field-key {
    color: #5c6a7e;
}

.fetcher-field-value {
    color: #8896a6;
}

.fetcher-field-sep {
    color: #4a5568;
    margin: 0 4px;
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

/* Pass-10 B1: every panel header strip uses one spec — same height,
   same padding, same hairline. */
.inspector-header {
    font-size: 12px;
    color: #a4b1c2;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 700;
    padding: 10px 14px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    display: flex;
    align-items: center;
    gap: 8px;
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
    padding: 1px 6px;
    margin: 0 -6px;
}

/* Pass-11 flash + persistent mark — every line that the diff flagged
   gets a soft tinted bg, an inset color bar on the left, and a
   one-shot animation that runs each time the model panel re-mounts
   (i.e. on every step transition, via the keyed wrapper). */

.dv-row.is-mutated {
    background: rgba(252, 211, 77, 0.10);
    box-shadow: inset 2px 0 0 #fcd34d;
}

.dv-row.is-added {
    background: rgba(134, 239, 172, 0.10);
    box-shadow: inset 2px 0 0 #86efac;
}

.dv-row.is-restructured {
    background: rgba(196, 181, 253, 0.10);
    box-shadow: inset 2px 0 0 #c4b5fd;
}

@keyframes dv-flash-yellow {
    0% { background: rgba(252, 211, 77, 0.55); }
    100% { background: rgba(252, 211, 77, 0.10); }
}

@keyframes dv-flash-green {
    0% { background: rgba(134, 239, 172, 0.55); }
    100% { background: rgba(134, 239, 172, 0.10); }
}

@keyframes dv-flash-purple {
    0% { background: rgba(196, 181, 253, 0.55); }
    100% { background: rgba(196, 181, 253, 0.10); }
}

.dv-row.flash-mutated {
    animation: dv-flash-yellow 1.1s ease-out;
}

.dv-row.flash-added {
    animation: dv-flash-green 1.1s ease-out;
}

.dv-row.flash-restructured {
    animation: dv-flash-purple 1.1s ease-out;
}

@media (prefers-reduced-motion: reduce) {
    .dv-row.flash-mutated,
    .dv-row.flash-added,
    .dv-row.flash-restructured {
        animation: none;
    }
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
