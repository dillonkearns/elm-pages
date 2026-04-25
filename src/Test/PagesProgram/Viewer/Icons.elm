module Test.PagesProgram.Viewer.Icons exposing
    ( Kind(..)
    , channelColorCookie
    , channelColorEffect
    , channelColorFetcher
    , channelColorNetworkBackend
    , channelColorNetworkFrontend
    , eventCheck
    , eventCookie
    , eventCookieSized
    , eventCross
    , eventDown
    , eventEffect
    , eventEffectSized
    , eventFetcher
    , eventFetcherResolve
    , eventFetcherSized
    , eventFetcherSubmit
    , eventNetwork
    , eventNetworkSized
    , eventUp
    , eventUpRight
    , kindColor
    , kindFromSnapshot
    , stepKind
    , stepKindFromKind
    , verbEye
    , verbEyeOff
    , verbFlag
    , verbIconForSnapshot
    , verbKeyboard
    , verbMouse
    , verbNav
    , verbPlay
    )

{-| SVG icons for the visual test viewer.

Sibling module to `Test.PagesProgram.Viewer` to keep that file from growing further.
Emits elements through `VirtualDom.nodeNS` with the SVG namespace so the package
does not need to take a dependency on `elm/svg`.

-}

import Html exposing (Html)
import Test.PagesProgram.Internal as Internal exposing (Snapshot)
import VirtualDom


{-| What to render. `StepKind` has 5 variants; we widen via label inference
so click vs fillIn, navigate, redirect, and "Has" vs "HasNot" each get their
own icon.
-}
type Kind
    = Start
    | Click
    | FillIn
    | Assert
    | AssertNot
    | Setup
    | Navigate
    | Redirect
    | Failure


{-| Pick the icon for a given snapshot, using label-prefix inference to split
Interaction into Click / FillIn / Navigate / Redirect, and Assertion into
Assert / AssertNot.
-}
kindFromSnapshot : Snapshot -> Kind
kindFromSnapshot snapshot =
    case snapshot.stepKind of
        Internal.Start ->
            Start

        Internal.Interaction ->
            if String.startsWith "fillIn" snapshot.label then
                FillIn

            else if String.startsWith "navigateTo" snapshot.label then
                Navigate

            else if String.startsWith "redirected" snapshot.label then
                Redirect

            else
                Click

        Internal.Assertion ->
            if String.contains "HasNot" snapshot.label then
                AssertNot

            else
                Assert

        Internal.EffectResolution ->
            Setup

        Internal.Error ->
            Failure


{-| Dispatch a snapshot to the verb icon set used in the step rail. Color
is hard-coded to `currentColor` so CSS drives the per-row state color
(yellow on hover, cyan on active, neutral otherwise).

`FillIn`, `Navigate`, and `Redirect` use the legacy I-beam / chain-link
/ boxed-301 icons (preferred over the keyboard / compass alternatives).
-}
verbIconForSnapshot : Snapshot -> Html msg
verbIconForSnapshot snapshot =
    let
        color =
            "currentColor"

        size =
            16
    in
    case kindFromSnapshot snapshot of
        Start ->
            verbFlag size color

        Click ->
            verbMouse size color

        FillIn ->
            iconFillIn color

        Assert ->
            verbEye size color

        AssertNot ->
            verbEyeOff size color

        Setup ->
            verbPlay size color

        Navigate ->
            iconLinkChain color

        Redirect ->
            iconRedirect color

        Failure ->
            iconWarn color


{-| Render the step-kind icon chosen for a snapshot, in its kind color.
-}
stepKind : Snapshot -> Html msg
stepKind snapshot =
    stepKindFromKind (kindFromSnapshot snapshot)


stepKindFromKind : Kind -> Html msg
stepKindFromKind kind =
    let
        color =
            kindColor kind
    in
    case kind of
        Start ->
            iconFlag color

        Click ->
            iconClick color

        FillIn ->
            iconFillIn color

        Assert ->
            iconMagnifier color

        AssertNot ->
            iconMagnifier color

        Setup ->
            iconPlay color

        Navigate ->
            iconLinkChain color

        Redirect ->
            iconRedirect color

        Failure ->
            iconWarn color


{-| Color palette tuned for the dark background rail.
-}
kindColor : Kind -> String
kindColor kind =
    case kind of
        Start ->
            "#86efac"

        Click ->
            "#7dd3fc"

        FillIn ->
            "#7dd3fc"

        Assert ->
            "#c4b5fd"

        AssertNot ->
            "#c4b5fd"

        Setup ->
            "#fcd34d"

        Navigate ->
            "#f472b6"

        Redirect ->
            "#c4b5fd"

        Failure ->
            "#e74c3c"



-- STEP-KIND ICONS (size 13–14, rendered next to the step number)


iconFlag : String -> Html msg
iconFlag color =
    svg "14" "14" "0 0 16 16"
        [ path
            [ attr "d" "M3 2v12.5"
            , attr "stroke" color
            , attr "stroke-width" "1.5"
            , attr "stroke-linecap" "round"
            ]
        , flagRect color "3.8" "2.8"
        , flagRect color "6.8" "2.8"
        , flagRect color "9.8" "2.8"
        , flagRect color "5.3" "4.15"
        , flagRect color "8.3" "4.15"
        , flagRect color "11.3" "4.15"
        , flagRect color "3.8" "5.5"
        , flagRect color "6.8" "5.5"
        , flagRect color "9.8" "5.5"
        ]


flagRect : String -> String -> String -> Html msg
flagRect color x y =
    rect
        [ attr "x" x
        , attr "y" y
        , attr "width" "1.5"
        , attr "height" "1.35"
        , attr "fill" color
        ]


iconClick : String -> Html msg
iconClick color =
    strokeSvg "13" "13" "0 0 16 16" color "1.6"
        [ path [ attr "d" "M4 2.5l8 4.5-3.5 1L7 12z" ]
        , path [ attr "d" "M9.5 10.5l2.5 2.5" ]
        ]


iconFillIn : String -> Html msg
iconFillIn color =
    strokeSvg "13" "13" "0 0 16 16" color "1.6"
        [ path [ attr "d" "M6 3h4M6 13h4" ]
        , path [ attr "d" "M8 3v10" ]
        ]


iconMagnifier : String -> Html msg
iconMagnifier color =
    strokeSvg "13" "13" "0 0 16 16" color "1.6"
        [ circle [ attr "cx" "7", attr "cy" "7", attr "r" "4" ]
        , path [ attr "d" "M10 10l3 3" ]
        ]


iconPlay : String -> Html msg
iconPlay color =
    svg "13" "13" "0 0 16 16"
        [ path [ attr "d" "M4 3l9 5-9 5z", attr "fill" color ] ]


iconLinkChain : String -> Html msg
iconLinkChain color =
    strokeSvg "13" "13" "0 0 16 16" color "1.6"
        [ path [ attr "d" "M6.5 9.5l3-3" ]
        , path [ attr "d" "M5 11a2.2 2.2 0 0 1-3.1-3.1L3.4 6.4a2.2 2.2 0 0 1 3.1 0" ]
        , path [ attr "d" "M11 5a2.2 2.2 0 0 1 3.1 3.1L12.6 9.6a2.2 2.2 0 0 1-3.1 0" ]
        ]


iconRedirect : String -> Html msg
iconRedirect color =
    svg "18" "12" "0 0 22 14"
        [ rect
            [ attr "x" "0.5"
            , attr "y" "0.5"
            , attr "width" "21"
            , attr "height" "13"
            , attr "rx" "2"
            , attr "fill" "none"
            , attr "stroke" color
            , attr "stroke-width" "1.2"
            ]
        , VirtualDom.nodeNS svgNS
            "text"
            [ attr "x" "11"
            , attr "y" "10"
            , attr "text-anchor" "middle"
            , attr "fill" color
            , attr "font-size" "8"
            , attr "font-weight" "700"
            , attr "font-family" "'JetBrains Mono', monospace"
            ]
            [ Html.text "301" ]
        ]


iconWarn : String -> Html msg
iconWarn color =
    strokeSvg "13" "13" "0 0 16 16" color "1.6"
        [ path [ attr "d" "M8 2 L14 13 L2 13 Z" ]
        , path [ attr "d" "M8 6v3.5" ]
        , circle
            [ attr "cx" "8"
            , attr "cy" "11.5"
            , attr "r" "0.5"
            , attr "fill" color
            ]
        ]



-- EVENT-CHANNEL ICONS (shared glyphs for rail dots, toolbar toggles,
-- panel headers, and empty states). The bare `eventX` helpers are
-- kept as 10px shortcuts for the rail; `eventXSized` takes an explicit
-- pixel size for the larger contexts.


eventNetwork : String -> Html msg
eventNetwork color =
    eventNetworkSized 12 color


eventNetworkSized : Int -> String -> Html msg
eventNetworkSized size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.4"
        [ circle [ attr "cx" "6", attr "cy" "6", attr "r" "4.2" ]
        , path [ attr "d" "M1.8 6h8.4M6 1.8c1.5 1.7 1.5 6.7 0 8.4M6 1.8c-1.5 1.7-1.5 6.7 0 8.4" ]
        ]


eventFetcher : String -> Html msg
eventFetcher color =
    eventFetcherSized 12 color


eventFetcherSized : Int -> String -> Html msg
eventFetcherSized size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.5"
        [ path [ attr "d" "M4 2v8M2.5 3.5L4 2l1.5 1.5" ]
        , path [ attr "d" "M8 10V2M6.5 8.5L8 10l1.5-1.5" ]
        ]


{-| Half of the fetcher glyph — only the up-arrow. For SUBMIT lane labels
where the "up" direction carries the semantics.
-}
eventFetcherSubmit : Int -> String -> Html msg
eventFetcherSubmit size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.5"
        [ path [ attr "d" "M6 2v8M4.5 3.5L6 2l1.5 1.5" ] ]


{-| Half of the fetcher glyph — only the down-arrow. For RESOLVE lane
labels.
-}
eventFetcherResolve : Int -> String -> Html msg
eventFetcherResolve size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.5"
        [ path [ attr "d" "M6 10V2M4.5 8.5L6 10l1.5-1.5" ] ]


eventCookie : String -> Html msg
eventCookie color =
    eventCookieSized 12 color


eventCookieSized : Int -> String -> Html msg
eventCookieSized size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.2"
        [ path [ attr "d" "M6 1.5a4.5 4.5 0 1 0 4.5 4.5c-1 0-1.8-.8-1.8-1.8 0-.9-.8-1.7-1.7-1.7-.6 0-1-.4-1-1z" ]
        , circle [ attr "cx" "4.5", attr "cy" "6", attr "r" "0.5", attr "fill" color ]
        , circle [ attr "cx" "6.5", attr "cy" "8", attr "r" "0.5", attr "fill" color ]
        , circle [ attr "cx" "8", attr "cy" "6.5", attr "r" "0.4", attr "fill" color ]
        ]


eventEffect : String -> Html msg
eventEffect color =
    eventEffectSized 12 color


eventEffectSized : Int -> String -> Html msg
eventEffectSized size color =
    let
        s =
            String.fromInt size
    in
    svg s s "0 0 12 12"
        [ path
            [ attr "d" "M6 1.5l.9 2.6L9.5 5l-2.6.9L6 8.5l-.9-2.6L2.5 5l2.6-.9z"
            , attr "fill" color
            ]
        , path
            [ attr "d" "M10 7.5l.4 1.1 1.1.4-1.1.4-.4 1.1-.4-1.1-1.1-.4 1.1-.4z"
            , attr "fill" color
            ]
        ]


-- EVENT-CHIP GLYPHS (9×9 default, stroke-based, used by the icon-event
-- timeline in the Network and Fetcher panels). All use viewBox 0 0 12 12
-- so the existing strokeSvg helper works. Pass "currentColor" as color to
-- let the icon inherit from CSS.


eventUp : Int -> String -> Html msg
eventUp size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.8"
        [ path [ attr "d" "M6 10V2" ]
        , path [ attr "d" "M3 5L6 2L9 5" ]
        ]


eventDown : Int -> String -> Html msg
eventDown size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.8"
        [ path [ attr "d" "M6 2V10" ]
        , path [ attr "d" "M3 7L6 10L9 7" ]
        ]


eventUpRight : Int -> String -> Html msg
eventUpRight size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "1.8"
        [ path [ attr "d" "M3 9L9 3" ]
        , path [ attr "d" "M4.5 3L9 3L9 7.5" ]
        ]


eventCheck : Int -> String -> Html msg
eventCheck size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "2"
        [ path [ attr "d" "M2.5 6.5L5 9L9.5 3.5" ] ]


eventCross : Int -> String -> Html msg
eventCross size color =
    let
        s =
            String.fromInt size
    in
    strokeSvg s s "0 0 12 12" color "2"
        [ path [ attr "d" "M3 3L9 9" ]
        , path [ attr "d" "M9 3L3 9" ]
        ]


{-| Channel color tokens. Each channel has one canonical color for
rail dots, panel headers, and empty-state glyphs. The toolbar is the
exception — toolbar buttons paint the glyph with the button's own
active/inactive color instead of the channel color, so all toggle
buttons read as a uniform row.
-}
channelColorNetworkBackend : String
channelColorNetworkBackend =
    "#7dd3fc"


channelColorNetworkFrontend : String
channelColorNetworkFrontend =
    "#38bdf8"


channelColorFetcher : String
channelColorFetcher =
    "#86efac"


channelColorCookie : String
channelColorCookie =
    "#fcd34d"


channelColorEffect : String
channelColorEffect =
    "#c4b5fd"



-- VERB ICONS (used by step-row's icon column to picture the step's verb).
-- All target a 12px render. Path data lifted from the Pass-5 mockup so the
-- viewer matches `Step List Icon-Driven.html` exactly. Pass `"currentColor"`
-- as the color to let CSS drive coloring per row state.


{-| Mouse pointer — used for click-style verbs (clickButton, clickLink,
selectOption, check, uncheck).
-}
verbMouse : Int -> String -> Html msg
verbMouse size color =
    let
        s =
            String.fromInt size
    in
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" s
        , attr "height" s
        , attr "viewBox" "0 0 14 14"
        ]
        [ path
            [ attr "d" "M3 2 L3 11 L5.5 8.5 L7 12 L8.5 11.5 L7 8 L10.5 8 Z"
            , attr "fill" color
            , attr "stroke" color
            , attr "stroke-width" "0.5"
            , attr "stroke-linejoin" "round"
            ]
        ]


{-| Keyboard with three keys + spacebar — used for fillIn-style verbs.
-}
verbKeyboard : Int -> String -> Html msg
verbKeyboard size color =
    let
        s =
            String.fromInt size
    in
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" s
        , attr "height" s
        , attr "viewBox" "0 0 14 14"
        , attr "fill" "none"
        , attr "stroke" color
        , attr "stroke-width" "1.1"
        , attr "stroke-linecap" "round"
        ]
        [ rect
            [ attr "x" "1.5"
            , attr "y" "4"
            , attr "width" "11"
            , attr "height" "6"
            , attr "rx" "1"
            ]
        , path [ attr "d" "M3.5 6 L4 6" ]
        , path [ attr "d" "M6 6 L6.5 6" ]
        , path [ attr "d" "M8.5 6 L9 6" ]
        , path [ attr "d" "M4 8.2 L10 8.2" ]
        ]


{-| Solid play triangle — used for simulate verbs (Custom, Command, Http).
-}
verbPlay : Int -> String -> Html msg
verbPlay size color =
    let
        s =
            String.fromInt size
    in
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" s
        , attr "height" s
        , attr "viewBox" "0 0 12 12"
        ]
        [ VirtualDom.nodeNS svgNS
            "polygon"
            [ attr "points" "3,2 10,6 3,10"
            , attr "fill" color
            ]
            []
        ]


{-| Eye — used for ensureView / expectView verbs.
-}
verbEye : Int -> String -> Html msg
verbEye size color =
    let
        s =
            String.fromInt size
    in
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" s
        , attr "height" s
        , attr "viewBox" "0 0 14 14"
        ]
        [ path
            [ attr "d" "M1.5 7 Q7 2.5 12.5 7 Q7 11.5 1.5 7 Z"
            , attr "stroke" color
            , attr "stroke-width" "1.1"
            , attr "fill" "none"
            ]
        , circle
            [ attr "cx" "7"
            , attr "cy" "7"
            , attr "r" "1.7"
            , attr "fill" color
            ]
        ]


{-| Eye with a slash through it — used for ensureViewHasNot / expectViewHasNot.
The slash is drawn as two stacked lines: a thicker dark line that "cuts"
the eye, then a thinner colored line on top.
-}
verbEyeOff : Int -> String -> Html msg
verbEyeOff size color =
    let
        s =
            String.fromInt size
    in
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" s
        , attr "height" s
        , attr "viewBox" "0 0 14 14"
        ]
        [ path
            [ attr "d" "M1.5 7 Q7 2.5 12.5 7 Q7 11.5 1.5 7 Z"
            , attr "stroke" color
            , attr "stroke-width" "1.1"
            , attr "fill" "none"
            ]
        , circle
            [ attr "cx" "7"
            , attr "cy" "7"
            , attr "r" "1.7"
            , attr "fill" color
            ]
        , path
            [ attr "d" "M2 12 L12 2"
            , attr "stroke" "#0d1117"
            , attr "stroke-width" "2.4"
            ]
        , path
            [ attr "d" "M2 12 L12 2"
            , attr "stroke" color
            , attr "stroke-width" "1.2"
            ]
        ]


{-| Checkered flag — used for the Start step. Wraps the existing
`iconFlag` SVG so callers can use the verb-icon signature.
-}
verbFlag : Int -> String -> Html msg
verbFlag size color =
    let
        s =
            String.fromInt size
    in
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" s
        , attr "height" s
        , attr "viewBox" "0 0 16 16"
        ]
        [ path
            [ attr "d" "M3 2v12.5"
            , attr "stroke" color
            , attr "stroke-width" "1.5"
            , attr "stroke-linecap" "round"
            ]
        , flagRect color "3.8" "2.8"
        , flagRect color "6.8" "2.8"
        , flagRect color "9.8" "2.8"
        , flagRect color "5.3" "4.15"
        , flagRect color "8.3" "4.15"
        , flagRect color "11.3" "4.15"
        , flagRect color "3.8" "5.5"
        , flagRect color "6.8" "5.5"
        , flagRect color "9.8" "5.5"
        ]


{-| Compass / location target — used for navigateTo / redirected /
ensureBrowserUrl verbs.
-}
verbNav : Int -> String -> Html msg
verbNav size color =
    let
        s =
            String.fromInt size
    in
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" s
        , attr "height" s
        , attr "viewBox" "0 0 14 14"
        ]
        [ circle
            [ attr "cx" "7"
            , attr "cy" "7"
            , attr "r" "5"
            , attr "stroke" color
            , attr "stroke-width" "1.2"
            , attr "fill" "none"
            ]
        , path
            [ attr "d" "M9.5 4.5 L6.5 7.5 M4.5 9.5 L6.5 7.5"
            , attr "stroke" color
            , attr "stroke-width" "1.2"
            , attr "stroke-linecap" "round"
            ]
        , circle
            [ attr "cx" "7"
            , attr "cy" "7"
            , attr "r" "1"
            , attr "fill" color
            ]
        ]



-- LOW-LEVEL HELPERS


svgNS : String
svgNS =
    "http://www.w3.org/2000/svg"


svg : String -> String -> String -> List (Html msg) -> Html msg
svg width height viewBox children =
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" width
        , attr "height" height
        , attr "viewBox" viewBox
        ]
        children


{-| SVG with shared stroke attrs — `fill="none"`, stroke color, stroke-width,
round caps + joins.
-}
strokeSvg : String -> String -> String -> String -> String -> List (Html msg) -> Html msg
strokeSvg width height viewBox color strokeWidth children =
    VirtualDom.nodeNS svgNS
        "svg"
        [ attr "width" width
        , attr "height" height
        , attr "viewBox" viewBox
        , attr "fill" "none"
        , attr "stroke" color
        , attr "stroke-width" strokeWidth
        , attr "stroke-linecap" "round"
        , attr "stroke-linejoin" "round"
        ]
        children


path : List (VirtualDom.Attribute msg) -> Html msg
path attrs =
    VirtualDom.nodeNS svgNS "path" attrs []


rect : List (VirtualDom.Attribute msg) -> Html msg
rect attrs =
    VirtualDom.nodeNS svgNS "rect" attrs []


circle : List (VirtualDom.Attribute msg) -> Html msg
circle attrs =
    VirtualDom.nodeNS svgNS "circle" attrs []


attr : String -> String -> VirtualDom.Attribute msg
attr =
    VirtualDom.attribute
