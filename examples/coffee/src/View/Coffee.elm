module View.Coffee exposing
    ( shell
    , brand, smallBrand, bagIcon, hero, infoStrip
    , sectionHead, productCard, stepperShell
    , cartPanel, cartLine, cartTotals, emptyCart
    , loginPage, loginAside, signupAside
    , checkoutPage, ReceiptLine
    )

{-| Pre-baked view helpers for the Blendhaus coffee shop demo.

The route modules describe **what** to show (data + actions). This module
describes **how** to lay it out, with class names that hook into `style.css`.

The split lets a live demo focus on `data`, `action`, forms, and optimistic UI
without having to type all the markup.

-}

import Data.Coffee exposing (Coffee)
import Html exposing (Html)
import Html.Attributes as Attr
import Svg
import Svg.Attributes as SA
import View.Drink



-- BRAND


brand : Html msg
brand =
    Html.div [ Attr.class "bh-brand" ]
        [ logo
        , Html.div []
            [ Html.div [ Attr.class "bh-brand-name bh-serif" ] [ Html.text "Blendhaus" ]
            , Html.div [ Attr.class "bh-brand-sub bh-mono" ] [ Html.text "coffee bar · est. 2026" ]
            ]
        ]


smallBrand : Html msg
smallBrand =
    Html.div [ Attr.class "bh-brand" ]
        [ logo
        , Html.div []
            [ Html.div [ Attr.class "bh-brand-name bh-serif" ] [ Html.text "Blendhaus" ]
            ]
        ]


logo : Html msg
logo =
    Svg.svg
        [ SA.viewBox "0 0 36 36"
        , SA.width "36"
        , SA.height "36"
        , Attr.attribute "aria-hidden" "true"
        ]
        [ Svg.circle
            [ SA.cx "18"
            , SA.cy "18"
            , SA.r "17"
            , SA.fill "none"
            , SA.stroke "var(--bh-ink)"
            , SA.strokeWidth "1"
            ]
            []
        , Svg.path
            [ SA.d "M11 22 Q18 8 25 22"
            , SA.stroke "var(--bh-ink)"
            , SA.strokeWidth "1.2"
            , SA.fill "none"
            ]
            []
        , Svg.circle
            [ SA.cx "18"
            , SA.cy "22"
            , SA.r "2"
            , SA.fill "var(--bh-ink)"
            ]
            []
        ]


bagIcon : Html msg
bagIcon =
    Svg.svg
        [ SA.viewBox "0 0 14 14"
        , SA.width "14"
        , SA.height "14"
        , Attr.attribute "aria-hidden" "true"
        ]
        [ Svg.path
            [ SA.d "M3 5h8l-0.6 6.5a1 1 0 0 1-1 0.9H4.6a1 1 0 0 1-1-0.9L3 5Z"
            , SA.fill "none"
            , SA.stroke "currentColor"
            , SA.strokeWidth "1.2"
            ]
            []
        , Svg.path
            [ SA.d "M5 5V3.5a2 2 0 0 1 4 0V5"
            , SA.fill "none"
            , SA.stroke "currentColor"
            , SA.strokeWidth "1.2"
            , SA.strokeLinecap "round"
            ]
            []
        ]



-- PAGE SHELL


{-| Sticky top bar with brand, nav links, optional avatar/signout, and a cart count chip.

Each interactive piece is passed in as `Html`, so the route owns the
session-clearing form / link to checkout / etc.

-}
shell :
    { greeting : Maybe String
    , signoutForm : Maybe (Html msg)
    , cartCount : Int
    , active : String
    }
    -> Html msg
shell { greeting, signoutForm, cartCount, active } =
    Html.header [ Attr.class "bh-header" ]
        [ Html.div [ Attr.class "bh-header-inner" ]
            [ brand
            , Html.nav [ Attr.class "bh-nav bh-mono" ]
                [ Html.a [ Attr.href "/", Attr.attribute "data-active" (boolAttr (active == "shop")) ] [ Html.text "Menu" ]
                , Html.a [ Attr.href "/checkout", Attr.attribute "data-active" (boolAttr (active == "checkout")) ] [ Html.text "Bag" ]
                ]
            , Html.div [ Attr.class "bh-header-right" ]
                [ greeting
                    |> Maybe.map (\name -> Html.span [ Attr.class "bh-account-meta bh-mono" ] [ Html.text ("hi, " ++ name) ])
                    |> Maybe.withDefault (Html.text "")
                , signoutForm |> Maybe.withDefault (Html.text "")
                , Html.a
                    [ Attr.href "/checkout", Attr.class "bh-cart-btn bh-mono" ]
                    [ bagIcon
                    , Html.span [] [ Html.text (" Bag · " ++ String.fromInt cartCount) ]
                    ]
                ]
            ]
        ]



-- HERO


hero : Html msg
hero =
    Html.section [ Attr.class "bh-hero" ]
        [ Html.h1 [ Attr.class "bh-hero-title" ]
            [ Html.text "Slow coffee,"
            , Html.br [] []
            , Html.text "poured "
            , Html.em [] [ Html.text "by hand." ]
            ]
        , Html.div [ Attr.class "bh-hero-meta" ]
            [ Html.div [ Attr.class "bh-eyebrow" ] [ Html.text "Spring menu · No. 14" ]
            , Html.p [] [ Html.text "Single-origin beans, ceremonial matcha, oat milk steamed to order. Sip at the bar, or take a bag to go." ]
            , Html.div [ Attr.class "bh-hero-stats" ]
                [ heroStat "06:30" "Doors open"
                , heroStat "22s" "Shot pull"
                , heroStat "$6" "Avg drink"
                ]
            ]
        ]


heroStat : String -> String -> Html msg
heroStat value label =
    Html.div [ Attr.class "bh-hero-stat" ]
        [ Html.div [ Attr.class "v" ] [ Html.text value ]
        , Html.div [ Attr.class "l" ] [ Html.text label ]
        ]



-- MENU


sectionHead : { name : String, ix : Int, count : Int } -> Html msg
sectionHead { name, ix, count } =
    Html.div [ Attr.class "bh-section-head" ]
        [ Html.h2 [] [ Html.text name ]
        , Html.div [ Attr.class "num" ]
            [ Html.text
                (String.padLeft 2 '0' (String.fromInt ix)
                    ++ " · "
                    ++ String.fromInt count
                    ++ " drinks"
                )
            ]
        ]


{-| One product tile: vignette, name, tagline, price, +/- stepper.

The route passes in `decrement` and `increment` already-rendered as forms,
so this helper is purely visual.

-}
productCard :
    { coffee : Coffee
    , qty : Int
    , isPending : Bool
    , decrement : Html msg
    , increment : Html msg
    }
    -> Html msg
productCard { coffee, qty, isPending, decrement, increment } =
    Html.li
        [ Attr.class "bh-product"
        , Attr.attribute "data-active" (boolAttr (qty > 0))
        ]
        [ Html.div
            [ Attr.class "bh-product-vignette"
            , Attr.attribute "style" ("--vignette-tint: " ++ vignetteFor coffee.variant)
            ]
            [ View.Drink.glyph coffee.variant 170 ]
        , Html.h3 [ Attr.class "bh-product-name" ]
            [ Html.span [] [ Html.text coffee.name ]
            , Html.span [ Attr.class "bh-product-price" ] [ Html.text ("$" ++ String.fromInt coffee.price ++ ".00") ]
            ]
        , Html.p [ Attr.class "bh-product-tagline" ] [ Html.text coffee.tagline ]
        , Html.div [ Attr.class "bh-product-actions" ]
            [ stepperShell { qty = qty, isPending = isPending, decrement = decrement, increment = increment }
            ]
        ]


{-| The +/- stepper layout. The route renders the actual buttons (as forms).
-}
stepperShell :
    { qty : Int
    , isPending : Bool
    , decrement : Html msg
    , increment : Html msg
    }
    -> Html msg
stepperShell { qty, isPending, decrement, increment } =
    Html.div
        [ Attr.class "bh-stepper"
        , Attr.attribute "data-active" (boolAttr (qty > 0))
        , Attr.attribute "data-pending" (boolAttr isPending)
        ]
        [ Html.div [ Attr.class "bh-stepper-btn-wrap" ] [ decrement ]
        , Html.div [ Attr.class "bh-stepper-qty bh-mono" ]
            [ Html.span [] [ Html.text (String.fromInt qty) ]
            , if isPending then
                Html.span [ Attr.class "bh-pending-dot", Attr.attribute "aria-hidden" "true", Attr.style "margin-left" "6px" ] []

              else
                Html.text ""
            ]
        , Html.div [ Attr.class "bh-stepper-btn-wrap" ] [ increment ]
        ]



-- CART PANEL


type alias ReceiptLine =
    { coffee : Coffee
    , qty : Int
    , isPending : Bool
    }


cartPanel :
    { lines : List ReceiptLine
    , subtotal : Int
    , tax : Int
    , total : Int
    , anyPending : Bool
    , checkout : Html msg
    }
    -> Html msg
cartPanel { lines, subtotal, tax, total, anyPending, checkout } =
    Html.aside [ Attr.class "bh-cart" ]
        [ Html.div [ Attr.class "bh-cart-head" ]
            [ Html.h3 [] [ Html.text "Bag" ]
            , Html.div [ Attr.class "cnt" ]
                [ Html.text
                    (String.fromInt (List.length lines)
                        ++ (if List.length lines == 1 then
                                " item"

                            else
                                " items"
                           )
                    )
                ]
            ]
        , if anyPending then
            Html.div
                [ Attr.class "bh-cart-status"
                , Attr.attribute "data-pending" "true"
                ]
                [ Html.span [ Attr.class "dot" ] []
                , Html.text "syncing"
                ]

          else
            Html.text ""
        , if List.isEmpty lines then
            emptyCart

          else
            Html.div []
                [ Html.div [ Attr.class "bh-cart-list" ] (List.map cartLine lines)
                , cartTotals { subtotal = subtotal, tax = tax, total = total, isPending = anyPending }
                ]
        , checkout
        ]


cartLine : ReceiptLine -> Html msg
cartLine { coffee, qty, isPending } =
    Html.div
        [ Attr.class "bh-cart-item"
        , Attr.attribute "data-pending" (boolAttr isPending)
        ]
        [ Html.div
            [ Attr.class "thumb"
            , Attr.attribute "style" ("--vignette-tint: " ++ vignetteFor coffee.variant)
            ]
            [ View.Drink.glyph coffee.variant 36 ]
        , Html.div [ Attr.class "meta" ]
            [ Html.div [ Attr.class "n" ] [ Html.text coffee.name ]
            , Html.div [ Attr.class "q" ]
                [ Html.span [] [ Html.text ("×" ++ String.fromInt qty) ]
                , if isPending then
                    Html.span []
                        [ Html.span [ Attr.class "bh-pending-dot" ] []
                        , Html.span [ Attr.style "color" "var(--bh-accent)", Attr.style "margin-left" "6px" ] [ Html.text "syncing" ]
                        ]

                  else
                    Html.text ""
                ]
            ]
        , Html.div [ Attr.class "price" ] [ Html.text ("$" ++ String.fromInt (coffee.price * qty) ++ ".00") ]
        ]


cartTotals : { subtotal : Int, tax : Int, total : Int, isPending : Bool } -> Html msg
cartTotals { subtotal, tax, total, isPending } =
    Html.div [ Attr.class "bh-cart-totals" ]
        [ totalsRow "Subtotal" subtotal False
        , totalsRow "Tax" tax False
        , Html.div [ Attr.class "row total" ]
            [ Html.span [] [ Html.text "Total" ]
            , Html.span
                [ Attr.class "v"
                , Attr.attribute "data-pending" (boolAttr isPending)
                ]
                [ Html.text ("$" ++ String.fromInt total ++ ".00") ]
            ]
        ]


totalsRow : String -> Int -> Bool -> Html msg
totalsRow label amount _ =
    Html.div [ Attr.class "row" ]
        [ Html.span [] [ Html.text label ]
        , Html.span [] [ Html.text ("$" ++ String.fromInt amount ++ ".00") ]
        ]


emptyCart : Html msg
emptyCart =
    Html.div [ Attr.class "bh-cart-empty" ]
        [ Html.div [ Attr.class "bh-serif" ] [ Html.text "Bag is empty." ]
        , Html.div
            [ Attr.class "bh-mono"
            , Attr.style "font-size" "11px"
            , Attr.style "color" "var(--bh-ink-3)"
            , Attr.style "margin-top" "6px"
            , Attr.style "letter-spacing" ".08em"
            ]
            [ Html.text "tap + on a drink to begin" ]
        ]



-- INFO FOOTER


infoStrip : Html msg
infoStrip =
    Html.div [ Attr.class "bh-info-strip" ]
        [ infoCol "Bar hours" "Mon–Sat · 6:30–18:00"
        , infoCol "Pickup" "Ready in ~6 minutes"
        , infoCol "Roasters" "12 small-batch"
        , infoCol "Beans" "Whole-bag delivery"
        ]


infoCol : String -> String -> Html msg
infoCol label value =
    Html.div [ Attr.class "col" ]
        [ Html.div [ Attr.class "l" ] [ Html.text label ]
        , Html.div [ Attr.class "v bh-serif" ] [ Html.text value ]
        ]



-- LOGIN PAGE


loginPage : { aside : Html msg, form : Html msg } -> Html msg
loginPage { aside, form } =
    Html.div [ Attr.class "bh-login-page" ]
        [ aside
        , Html.div [ Attr.class "bh-login-form-wrap" ] [ form ]
        ]


loginAside : Html msg
loginAside =
    Html.aside [ Attr.class "bh-login-aside" ]
        [ brand
        , Html.div [ Attr.class "quote" ]
            [ Html.text "The smallest "
            , Html.em [] [ Html.text "sip" ]
            , Html.text " of spring,"
            , Html.br [] []
            , Html.text "before the day begins."
            ]
        , Html.div [ Attr.class "credit" ] [ Html.text "— Volume 14 · Mar–May" ]
        , Html.div [ Attr.class "glow" ] []
        , Html.div [ Attr.class "glow b" ] []
        ]


signupAside : Html msg
signupAside =
    Html.aside [ Attr.class "bh-login-aside" ]
        [ brand
        , Html.div [ Attr.class "quote" ]
            [ Html.text "Your "
            , Html.em [] [ Html.text "regular," ]
            , Html.br [] []
            , Html.text "remembered."
            ]
        , Html.div [ Attr.class "credit" ] [ Html.text "— Members · est. 2026" ]
        , Html.div [ Attr.class "glow" ] []
        , Html.div [ Attr.class "glow b" ] []
        ]



-- CHECKOUT


checkoutPage :
    { greeting : Maybe String
    , signoutForm : Maybe (Html msg)
    , cartCount : Int
    , lines : List ReceiptLine
    , subtotal : Int
    , tax : Int
    , total : Int
    , placeOrderForm : Html msg
    }
    -> List (Html msg)
checkoutPage opts =
    [ shell
        { greeting = opts.greeting
        , signoutForm = opts.signoutForm
        , cartCount = opts.cartCount
        , active = "checkout"
        }
    , Html.div [ Attr.class "bh-checkout-wrap" ]
        [ Html.div []
            [ Html.div [ Attr.class "crumb" ] [ Html.text "Bag → Checkout → Confirmation" ]
            , Html.h1 [] [ Html.text "Almost there." ]
            , Html.p
                [ Attr.style "color" "var(--bh-ink-3)"
                , Attr.style "margin" "0 0 28px"
                , Attr.style "max-width" "50ch"
                ]
                [ Html.text "Drinks are pulled fresh when you arrive. We'll text you when your order is at the bar." ]
            , Html.section [ Attr.class "bh-co-section" ]
                [ Html.h3 []
                    [ Html.text "When?"
                    , Html.span [ Attr.class "step" ] [ Html.text "step 01 / 02" ]
                    ]
                , Html.div [ Attr.class "bh-options", Attr.style "grid-template-columns" "repeat(3,1fr)" ]
                    [ pickupOption "asap" "As soon as possible" "~6 min" True
                    , pickupOption "830" "8:30 am" "in 42 min" False
                    , pickupOption "1200" "12:00 pm" "lunch break" False
                    ]
                ]
            , Html.section [ Attr.class "bh-co-section" ]
                [ Html.h3 []
                    [ Html.text "Payment"
                    , Html.span [ Attr.class "step" ] [ Html.text "on file" ]
                    ]
                , Html.div
                    [ Attr.class "bh-option"
                    , Attr.attribute "data-checked" "true"
                    , Attr.style "display" "flex"
                    , Attr.style "justify-content" "space-between"
                    , Attr.style "align-items" "center"
                    ]
                    [ Html.div []
                        [ Html.div [ Attr.class "l", Attr.style "font-size" "16px" ] [ Html.text "Visa ending 4214" ]
                        , Html.div [ Attr.class "s" ] [ Html.text "Expires 09 / 28" ]
                        ]
                    , Html.text ""
                    ]
                ]
            ]
        , Html.aside [ Attr.class "bh-co-summary" ]
            [ Html.h4 []
                [ Html.text "Order summary "
                , Html.span [ Attr.class "ix" ] [ Html.text (String.fromInt (List.length opts.lines) ++ " drinks") ]
                ]
            , Html.div [] (List.map receiptLine opts.lines)
            , Html.div [ Attr.class "bh-receipt" ]
                [ totalsRow "Subtotal" opts.subtotal False
                , totalsRow "Tax" opts.tax False
                , Html.div [ Attr.class "row total" ]
                    [ Html.span [] [ Html.text "Total" ]
                    , Html.span [ Attr.class "v" ] [ Html.text ("$" ++ String.fromInt opts.total ++ ".00") ]
                    ]
                ]
            , opts.placeOrderForm
            , Html.div
                [ Attr.style "text-align" "center"
                , Attr.style "margin-top" "10px"
                , Attr.style "font-family" "var(--mono)"
                , Attr.style "font-size" "10px"
                , Attr.style "letter-spacing" ".1em"
                , Attr.style "color" "var(--bh-ink-3)"
                ]
                [ Html.text "secured · session signed" ]
            ]
        ]
    ]


pickupOption : String -> String -> String -> Bool -> Html msg
pickupOption _ label sublabel checked =
    Html.div
        [ Attr.class "bh-option"
        , Attr.attribute "data-checked" (boolAttr checked)
        ]
        [ Html.div [ Attr.class "l", Attr.style "font-size" "16px" ] [ Html.text label ]
        , Html.div [ Attr.class "s" ] [ Html.text sublabel ]
        ]


receiptLine : ReceiptLine -> Html msg
receiptLine { coffee, qty } =
    Html.div [ Attr.class "bh-co-line" ]
        [ Html.div
            [ Attr.class "swatch"
            , Attr.attribute "style" ("--swatch: " ++ swatchFor coffee.variant)
            ]
            []
        , Html.div []
            [ Html.div [ Attr.class "n" ] [ Html.text coffee.name ]
            , Html.div [ Attr.class "q" ] [ Html.text ("×" ++ String.fromInt qty ++ " · " ++ coffee.tagline) ]
            ]
        , Html.div [ Attr.class "p" ] [ Html.text ("$" ++ String.fromInt (coffee.price * qty) ++ ".00") ]
        ]



-- THEME LOOKUPS


vignetteFor : String -> String
vignetteFor variant =
    case variant of
        "latte" ->
            "oklch(0.95 0.045 55)"

        "matcha" ->
            "oklch(0.95 0.030 145)"

        "espresso" ->
            "oklch(0.94 0.030 65)"

        "ube" ->
            "oklch(0.95 0.035 290)"

        "matchaLem" ->
            "oklch(0.95 0.040 25)"

        "golden" ->
            "oklch(0.97 0.045 95)"

        "drip" ->
            "oklch(0.94 0.030 65)"

        _ ->
            "oklch(0.95 0.020 80)"


swatchFor : String -> String
swatchFor variant =
    case variant of
        "latte" ->
            "#cdb38a"

        "matcha" ->
            "#8aa860"

        "espresso" ->
            "#3b2412"

        "ube" ->
            "#a98ec7"

        "matchaLem" ->
            "#b9cf80"

        "golden" ->
            "#e8b75a"

        "drip" ->
            "#7a4a25"

        _ ->
            "#cdb38a"


boolAttr : Bool -> String
boolAttr b =
    if b then
        "true"

    else
        "false"
