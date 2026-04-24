module Test.PagesProgram.Viewer.Icons exposing
    ( Kind(..)
    , eventCookie
    , eventEffect
    , eventFetcher
    , eventNetwork
    , kindColor
    , kindFromSnapshot
    , stepKind
    , stepKindFromKind
    )

{-| SVG icons for the visual test viewer.

Sibling module to `Test.PagesProgram.Viewer` to keep that file from growing further.
Emits elements through `VirtualDom.nodeNS` with the SVG namespace so the package
does not need to take a dependency on `elm/svg`.

-}

import Html exposing (Html)
import Test.PagesProgram.Internal as Internal exposing (Snapshot)
import VirtualDom


{-| What to render. `StepKind` has 5 variants; we widen to 8 via label inference
so click vs fillIn, navigate, and redirect each get their own icon.
-}
type Kind
    = Start
    | Click
    | FillIn
    | Assert
    | Setup
    | Navigate
    | Redirect
    | Failure


{-| Pick the icon for a given snapshot, using label-prefix inference to split
Interaction into Click / FillIn / Navigate / Redirect.
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
            Assert

        Internal.EffectResolution ->
            Setup

        Internal.Error ->
            Failure


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



-- EVENT-CHANNEL ICONS (size 10, rendered on the right edge of the step row)


eventNetwork : String -> Html msg
eventNetwork color =
    strokeSvg "10" "10" "0 0 12 12" color "1.4"
        [ circle [ attr "cx" "6", attr "cy" "6", attr "r" "4.2" ]
        , path [ attr "d" "M1.8 6h8.4M6 1.8c1.5 1.7 1.5 6.7 0 8.4M6 1.8c-1.5 1.7-1.5 6.7 0 8.4" ]
        ]


eventFetcher : String -> Html msg
eventFetcher color =
    strokeSvg "10" "10" "0 0 12 12" color "1.5"
        [ path [ attr "d" "M4 2v8M2.5 3.5L4 2l1.5 1.5" ]
        , path [ attr "d" "M8 10V2M6.5 8.5L8 10l1.5-1.5" ]
        ]


eventCookie : String -> Html msg
eventCookie color =
    strokeSvg "10" "10" "0 0 12 12" color "1.2"
        [ path [ attr "d" "M6 1.5a4.5 4.5 0 1 0 4.5 4.5c-1 0-1.8-.8-1.8-1.8 0-.9-.8-1.7-1.7-1.7-.6 0-1-.4-1-1z" ]
        , circle [ attr "cx" "4.5", attr "cy" "6", attr "r" "0.5", attr "fill" color ]
        , circle [ attr "cx" "6.5", attr "cy" "8", attr "r" "0.5", attr "fill" color ]
        , circle [ attr "cx" "8", attr "cy" "6.5", attr "r" "0.4", attr "fill" color ]
        ]


eventEffect : String -> Html msg
eventEffect color =
    svg "10" "10" "0 0 12 12"
        [ path
            [ attr "d" "M6 1.5l.9 2.6L9.5 5l-2.6.9L6 8.5l-.9-2.6L2.5 5l2.6-.9z"
            , attr "fill" color
            ]
        , path
            [ attr "d" "M10 7.5l.4 1.1 1.1.4-1.1.4-.4 1.1-.4-1.1-1.1-.4 1.1-.4z"
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
