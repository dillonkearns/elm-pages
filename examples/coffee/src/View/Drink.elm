module View.Drink exposing (glyph)

{-| Hand-drawn SVG illustrations for the seven Blendhaus drinks, ported from
the design's `drink.jsx`. All glyphs share a 120×130 viewBox and a wobbly
ink outline; the colored "wash" sits slightly off-register from the outline
to mimic watercolor.

Uses `elm/svg` so elements land in the SVG namespace — `Html.node "svg" …`
creates an inert HTML element, which is why your browser was rendering
nothing.

-}

import Html exposing (Html)
import Html.Attributes as HA
import Svg exposing (Svg)
import Svg.Attributes as A



-- ENTRY POINT


glyph : String -> Int -> Html msg
glyph variant size =
    case variant of
        "latte" ->
            latteCup size

        "espresso" ->
            espressoCup size

        "golden" ->
            goldenMug size

        "drip" ->
            paperCup size

        "matcha" ->
            matchaBowl size

        "ube" ->
            ubeGlass size

        "matchaLem" ->
            icedTumbler size

        _ ->
            latteCup size



-- PALETTE (lifted verbatim from drink.jsx)


ink : String
ink =
    "#1f1a14"


cream : String
cream =
    "#f3e7d4"


paper : String
paper =
    "#fdfaf3"


paperDeep : String
paperDeep =
    "#ece2cf"


latteColor : String
latteColor =
    "#cdb38a"


latteHi : String
latteHi =
    "#8a6a3f"


espressoColor : String
espressoColor =
    "#3b2412"


espressoHi : String
espressoHi =
    "#1a0c04"


goldenColor : String
goldenColor =
    "#e8b75a"


goldenHi : String
goldenHi =
    "#b3812a"


dripColor : String
dripColor =
    "#7a4a25"


dripHi : String
dripHi =
    "#3a2010"


matchaColor : String
matchaColor =
    "#8aa860"


matchaHi : String
matchaHi =
    "#5e7a3a"


ubeColor : String
ubeColor =
    "#a98ec7"


ubeHi : String
ubeHi =
    "#6f4f99"


lemA : String
lemA =
    "#b9cf80"


lemB : String
lemB =
    "#f1d56a"



-- SHARED HELPERS


svgRoot : Int -> List (Svg msg) -> Html msg
svgRoot size children =
    Svg.svg
        [ A.width (String.fromInt size)
        , A.height (String.fromInt (size * 130 // 120))
        , A.viewBox "0 0 120 130"
        , HA.attribute "aria-hidden" "true"
        ]
        children


{-| Wobbly ink stroke, no fill, rounded line caps — the "sketch" group.
-}
sketchGroup : List (Svg msg) -> Svg msg
sketchGroup children =
    Svg.g
        [ A.fill "none"
        , A.stroke ink
        , A.strokeWidth "1.6"
        , A.strokeLinecap "round"
        , A.strokeLinejoin "round"
        ]
        children


{-| Watercolor wash: filled shape, slightly off-register from the outline,
low opacity so the paper shows through.
-}
wash : { d : String, color : String, dx : Float, dy : Float, opacity : Float } -> Svg msg
wash w =
    Svg.path
        [ A.d w.d
        , A.fill w.color
        , A.opacity (String.fromFloat w.opacity)
        , A.transform ("translate(" ++ String.fromFloat w.dx ++ " " ++ String.fromFloat w.dy ++ ")")
        ]
        []


washDefault : String -> String -> Svg msg
washDefault d color =
    wash { d = d, color = color, dx = 1.5, dy = -1.2, opacity = 0.55 }



-- 1. CAFÉ LATTE — wide ceramic mug, watercolor wash + foam heart


latteCup : Int -> Html msg
latteCup size =
    let
        body =
            "M32 53 L80 52 L75 95 Q75 100 70 100 L42 100 Q36 100 36 95 Z"
    in
    svgRoot size
        [ washDefault body latteColor
        , sketchGroup
            [ Svg.path [ A.d "M30 51 L82 50 L77 96 Q77 102 71 102 L41 102 Q35 102 34 96 L30 51 Z" ] []
            , Svg.path [ A.d "M30 51 q26 -5 52 -1" ] []
            , Svg.path [ A.d "M82 60 q14 1 13 14 t-14 14" ] []
            ]
        , Svg.path
            [ A.d "M44 50 q12 -3 24 0 q-6 4 -12 4 q-6 0 -12 -4z"
            , A.fill cream
            , A.stroke latteHi
            , A.strokeWidth "0.8"
            ]
            []
        , Svg.g
            [ A.fill latteHi, A.opacity "0.5" ]
            [ Svg.circle [ A.cx "48", A.cy "50.5", A.r "0.5" ] []
            , Svg.circle [ A.cx "64", A.cy "50.5", A.r "0.5" ] []
            ]
        ]



-- 2. ESPRESSO — demitasse on saucer


espressoCup : Int -> Html msg
espressoCup size =
    let
        body =
            "M42 64 L72 64 L69 91 Q68 94 65 94 L49 94 Q46 94 45 91 Z"
    in
    svgRoot size
        [ wash { d = body, color = espressoColor, dx = 1.2, dy = -1, opacity = 0.5 }
        , sketchGroup
            [ Svg.path [ A.d "M40 62 L74 62 L71 92 Q70 96 66 96 L48 96 Q44 96 43 92 Z" ] []
            , Svg.ellipse [ A.cx "57", A.cy "62", A.rx "17", A.ry "3" ] []
            , Svg.path [ A.d "M74 70 q10 0 10 10 t-10 10" ] []
            , Svg.ellipse [ A.cx "57", A.cy "100", A.rx "28", A.ry "3" ] []
            ]
        , Svg.ellipse [ A.cx "57", A.cy "62", A.rx "14", A.ry "2.4", A.fill latteHi, A.opacity "0.7" ] []
        , Svg.g [ A.fill espressoHi, A.opacity "0.7" ]
            [ Svg.circle [ A.cx "52", A.cy "62", A.r "0.6" ] []
            , Svg.circle [ A.cx "60", A.cy "62.5", A.r "0.5" ] []
            , Svg.circle [ A.cx "64", A.cy "62", A.r "0.5" ] []
            ]
        ]



-- 3. GOLDEN LATTE — neutral ceramic body, surface only is colored


goldenMug : Int -> Html msg
goldenMug size =
    svgRoot size
        [ sketchGroup
            [ Svg.path [ A.d "M28 48 Q29 40 36 40 L78 40 Q86 40 86 49 L84 96 Q83 102 76 102 L38 102 Q31 102 30 96 Z" ] []
            , Svg.ellipse [ A.cx "86", A.cy "68", A.rx "8", A.ry "11" ] []
            ]
        , Svg.ellipse [ A.cx "57", A.cy "40", A.rx "29", A.ry "4", A.fill paper, A.stroke ink, A.strokeWidth "1.6" ] []
        , Svg.ellipse [ A.cx "57", A.cy "40", A.rx "26", A.ry "3", A.fill goldenColor ] []
        , Svg.ellipse [ A.cx "57", A.cy "40", A.rx "26", A.ry "3", A.fill "none", A.stroke goldenHi, A.strokeWidth "0.6", A.opacity "0.6" ] []
        , Svg.g [ A.fill goldenHi, A.opacity "0.7" ]
            [ Svg.circle [ A.cx "46", A.cy "40", A.r "0.6" ] []
            , Svg.circle [ A.cx "54", A.cy "40.5", A.r "0.5" ] []
            , Svg.circle [ A.cx "62", A.cy "40", A.r "0.6" ] []
            , Svg.circle [ A.cx "68", A.cy "40.5", A.r "0.5" ] []
            ]
        , Svg.g [ A.transform "translate(58 40)", A.opacity "0.85" ]
            [ Svg.g [ A.stroke goldenHi, A.strokeWidth "0.6", A.fill goldenColor ]
                [ Svg.ellipse [ A.rx "0.8", A.ry "2" ] []
                , Svg.ellipse [ A.rx "0.8", A.ry "2", A.transform "rotate(45)" ] []
                , Svg.ellipse [ A.rx "0.8", A.ry "2", A.transform "rotate(90)" ] []
                , Svg.ellipse [ A.rx "0.8", A.ry "2", A.transform "rotate(135)" ] []
                ]
            ]
        ]



-- 4. DRIP COFFEE — paper cup with sleeve + lid


paperCup : Int -> Html msg
paperCup size =
    let
        body =
            "M34 38 L78 38 L74 100 Q73 104 68 104 L44 104 Q39 104 38 100 Z"
    in
    svgRoot size
        [ wash { d = body, color = paperDeep, dx = 1.5, dy = -1.2, opacity = 0.7 }
        , sketchGroup
            [ Svg.path [ A.d body ] []
            , Svg.path [ A.d "M30 30 L82 30 L80 38 L32 38 Z" ] []
            , Svg.ellipse [ A.cx "56", A.cy "30", A.rx "26", A.ry "3" ] []
            , Svg.path [ A.d "M36 64 L76 64 L74 80 L38 80 Z" ] []
            , Svg.ellipse [ A.cx "74", A.cy "29", A.rx "3", A.ry "1" ] []
            ]
        , Svg.path [ A.d "M36 64 L76 64 L74 80 L38 80 Z", A.fill dripColor, A.opacity "0.55" ] []
        , Svg.path [ A.d "M36 64 L76 64", A.stroke dripHi, A.strokeWidth "0.7", A.opacity "0.5", A.fill "none" ] []
        , Svg.path [ A.d "M38 80 L74 80", A.stroke dripHi, A.strokeWidth "0.7", A.opacity "0.5", A.fill "none" ] []
        , Svg.path [ A.d "M30 30 L82 30 L80 38 L32 38 Z", A.fill espressoColor, A.opacity "0.85" ] []
        , Svg.ellipse [ A.cx "56", A.cy "30", A.rx "26", A.ry "3", A.fill espressoHi, A.opacity "0.8" ] []
        , Svg.text_
            [ A.x "56"
            , A.y "74"
            , A.textAnchor "middle"
            , A.fontFamily "monospace"
            , A.fontSize "4"
            , A.fill dripHi
            , A.opacity "0.85"
            ]
            [ Svg.text "BLENDHAUS" ]
        ]



-- 5. MATCHA LATTE — chawan, neutral body, matcha surface


matchaBowl : Int -> Html msg
matchaBowl size =
    svgRoot size
        [ sketchGroup
            [ Svg.path [ A.d "M24 64 Q24 96 56 101 Q88 96 88 64 Z" ] [] ]
        , Svg.ellipse [ A.cx "56", A.cy "64", A.rx "32", A.ry "5", A.fill paper, A.stroke ink, A.strokeWidth "1.6" ] []
        , Svg.ellipse [ A.cx "56", A.cy "64", A.rx "29", A.ry "4", A.fill matchaColor ] []
        , Svg.ellipse [ A.cx "50", A.cy "63", A.rx "14", A.ry "1.6", A.fill "#cfe1a4", A.opacity "0.85" ] []
        , Svg.ellipse [ A.cx "62", A.cy "65", A.rx "8", A.ry "1.1", A.fill "#e3eebc", A.opacity "0.8" ] []
        , Svg.g [ A.fill "#f7f3df" ]
            [ Svg.circle [ A.cx "46", A.cy "63.5", A.r "0.5" ] []
            , Svg.circle [ A.cx "52", A.cy "65", A.r "0.4" ] []
            , Svg.circle [ A.cx "64", A.cy "63.5", A.r "0.5" ] []
            , Svg.circle [ A.cx "68", A.cy "65", A.r "0.4" ] []
            ]
        , Svg.path
            [ A.d "M32 72 Q34 84 32 96"
            , A.stroke matchaHi
            , A.strokeWidth "1.2"
            , A.fill "none"
            , A.strokeLinecap "round"
            , A.opacity "0.45"
            ]
            []
        ]



-- 6. UBE LATTE — straight glass mug, two-tone (cream top, ube body)


ubeGlass : Int -> Html msg
ubeGlass size =
    let
        top =
            "M36 38 L76 38 L75 52 L37 52 Z"

        body =
            "M37 52 L75 52 L72 100 Q72 102 68 102 L44 102 Q40 102 40 100 Z"
    in
    svgRoot size
        [ wash { d = body, color = ubeColor, dx = 1.5, dy = -1.5, opacity = 0.55 }
        , wash { d = top, color = cream, dx = 1.5, dy = -1.5, opacity = 0.85 }
        , sketchGroup
            [ Svg.path [ A.d "M34 36 L78 36 L74 100 Q73 104 68 104 L44 104 Q39 104 38 100 Z" ] []
            , Svg.path [ A.d "M78 50 q12 0 12 14 t-12 14" ] []
            , Svg.ellipse [ A.cx "56", A.cy "36", A.rx "22", A.ry "3" ] []
            , Svg.path [ A.d "M36 50 L76 50" ] []
            ]
        , Svg.path
            [ A.d "M38 51 Q50 47 56 52 Q64 57 74 49"
            , A.stroke ubeHi
            , A.strokeWidth "0.9"
            , A.fill "none"
            , A.opacity "0.6"
            ]
            []
        , Svg.path
            [ A.d "M40 56 Q38 80 42 100"
            , A.stroke "#fff"
            , A.strokeOpacity "0.7"
            , A.strokeWidth "1.2"
            , A.fill "none"
            , A.strokeLinecap "round"
            ]
            []
        ]



-- 7. MATCHA LEMONADE — iced tumbler, two-tone, ice + lemon slice


icedTumbler : Int -> Html msg
icedTumbler size =
    let
        top =
            "M36 38 L77 38 L77 70 L36 70 Z"

        bottom =
            "M36 70 L77 70 L78 102 L36 102 Q36 102 36 102 Z"
    in
    svgRoot size
        [ wash { d = top, color = lemA, dx = 1.2, dy = -1.2, opacity = 0.6 }
        , wash { d = bottom, color = lemB, dx = 1.2, dy = -1, opacity = 0.6 }
        , sketchGroup
            [ Svg.path [ A.d "M36 36 L76 36 L78 102 Q78 104 76 104 L36 104 Q34 104 34 102 Z" ] []
            , Svg.path [ A.d "M32 36 Q56 14 80 36" ] []
            , Svg.rect [ A.x "32", A.y "34", A.width "48", A.height "3" ] []
            , Svg.path [ A.d "M62 22 L65 92", A.transform "rotate(8 62 50)" ] []
            ]
        , Svg.g [ A.transform "translate(58 86)" ]
            [ Svg.circle [ A.r "5", A.fill lemB, A.stroke goldenHi, A.strokeWidth "0.7" ] []
            , Svg.circle [ A.r "3", A.fill "none", A.stroke goldenHi, A.strokeWidth "0.4", A.opacity "0.7" ] []
            , Svg.path
                [ A.d "M0 -3.5 L0 3.5 M-3.5 0 L3.5 0 M-2.5 -2.5 L2.5 2.5 M2.5 -2.5 L-2.5 2.5"
                , A.stroke goldenHi
                , A.strokeWidth "0.3"
                , A.opacity "0.6"
                ]
                []
            ]
        , Svg.g
            [ A.fill "rgba(255,255,255,0.6)"
            , A.stroke "rgba(255,255,255,0.85)"
            , A.strokeWidth "0.5"
            ]
            [ iceCube { x = 42, y = 56, w = 9, rotate = -12, cx = 46.5, cy = 60.5 }
            , iceCube { x = 58, y = 50, w = 8, rotate = 8, cx = 62, cy = 54 }
            , iceCube { x = 66, y = 64, w = 7, rotate = -6, cx = 69.5, cy = 67.5 }
            , iceCube { x = 46, y = 74, w = 8, rotate = 14, cx = 50, cy = 78 }
            ]
        , Svg.g [ A.fill "rgba(255,255,255,0.85)" ]
            [ Svg.circle [ A.cx "40", A.cy "92", A.r "0.7" ] []
            , Svg.circle [ A.cx "42", A.cy "98", A.r "0.5" ] []
            , Svg.circle [ A.cx "74", A.cy "88", A.r "0.7" ] []
            , Svg.circle [ A.cx "72", A.cy "98", A.r "0.5" ] []
            ]
        ]


iceCube : { x : Float, y : Float, w : Float, rotate : Float, cx : Float, cy : Float } -> Svg msg
iceCube c =
    Svg.rect
        [ A.x (String.fromFloat c.x)
        , A.y (String.fromFloat c.y)
        , A.width (String.fromFloat c.w)
        , A.height (String.fromFloat c.w)
        , A.rx "1.5"
        , A.transform
            ("rotate(" ++ String.fromFloat c.rotate ++ " " ++ String.fromFloat c.cx ++ " " ++ String.fromFloat c.cy ++ ")")
        ]
        []
