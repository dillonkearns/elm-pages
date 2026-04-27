module Route.Index exposing (ActionData, Data, Model, Msg, route)

{-| The shop. Loads the menu + user + cart, renders the menu and cart, and
handles add-to-cart + sign-out form submissions.

This route is the showcase: `Model` is `{}`, `Msg` is `NoOp`, `update` is
untouched. All server interaction flows through `data`, `action`, and forms.

-}

import BackendTask exposing (BackendTask)
import Data.Coffee as Coffee exposing (Coffee)
import Data.CoffeeCart as Cart exposing (Cart)
import Data.CoffeeUser as User exposing (User)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.Handler
import Form.Validation as Validation
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Pages.ConcurrentSubmission
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)
import View.Coffee


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


type alias Data =
    { coffees : List Coffee
    , user : User
    , cart : Maybe Cart
    }


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init _ _ =
    ( {}, Effect.none )


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ NoOp model =
    ( model, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions _ _ _ _ =
    Sub.none


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []



-- DATA: load coffees + user + cart in parallel, redirecting to /login if no session


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data _ request =
    MySession.expectSessionDataOrRedirect (Session.get "userId")
        (\userId session ->
            BackendTask.map3 Data
                Coffee.all
                (User.find userId)
                (Cart.get userId)
                |> BackendTask.map Response.render
                |> BackendTask.map (Tuple.pair session)
        )
        request



-- ACTIONS: signout clears the session; setQuantity inserts a coffee_orders row


type Action
    = Signout
    | SetQuantity String Int


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action _ request =
    MySession.expectSessionDataOrRedirect (Session.get "userId")
        (\userId session ->
            case request |> Request.formData formHandlers of
                Just ( _, Form.Valid Signout ) ->
                    BackendTask.succeed (Route.redirectTo Route.Login)
                        |> BackendTask.map (Tuple.pair Session.empty)

                Just ( _, Form.Valid (SetQuantity coffeeId quantity) ) ->
                    Cart.addItemToCart quantity userId coffeeId
                        |> BackendTask.map (\_ -> Response.render {})
                        |> BackendTask.map (Tuple.pair session)

                _ ->
                    BackendTask.succeed
                        ( session
                        , Response.errorPage (ErrorPage.internalError "Unexpected form data.")
                        )
        )
        request



-- FORMS: a sign-out form, and a set-quantity form for each +/- click.


type QuantityChange
    = Increment
    | Decrement


signoutForm : Form.HtmlForm String () input msg
signoutForm =
    Form.form
        { combine = Validation.succeed ()
        , view =
            \_ ->
                [ Html.button [ Attr.class "bh-link" ] [ Html.text "sign out" ] ]
        }
        |> Form.hiddenKind ( "kind", "signout" ) "Expected signout"


setQuantityForm : Form.HtmlForm String ( String, Int ) ( Int, QuantityChange, Coffee ) msg
setQuantityForm =
    Form.form
        (\coffeeId quantity ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap coffeeId
                    |> Validation.andMap quantity
            , view =
                \formState ->
                    let
                        ( _, change, _ ) =
                            formState.input
                    in
                    [ Html.button [ Attr.class "bh-stepper-btn" ]
                        [ Html.text
                            (case change of
                                Increment ->
                                    "+"

                                Decrement ->
                                    "−"
                            )
                        ]
                    ]
            }
        )
        |> Form.hiddenKind ( "kind", "setQuantity" ) "Expected setQuantity"
        |> Form.hiddenField "coffeeId"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\( _, _, item ) -> item.id)
            )
        |> Form.hiddenField "quantity"
            (Field.int { invalid = \_ -> "Expected int" }
                |> Field.required "Required"
                |> Field.withInitialValue
                    (\( quantityInCart, change, _ ) ->
                        quantityInCart + toQuantity change
                    )
                |> Field.withMin 0 "Must be 0 or more"
            )


toQuantity : QuantityChange -> Int
toQuantity change =
    case change of
        Increment ->
            1

        Decrement ->
            -1


formHandlers : Form.Handler.Handler String Action
formHandlers =
    Form.Handler.init (\() -> Signout) signoutForm
        |> Form.Handler.with (\( id, qty ) -> SetQuantity id qty) setQuantityForm



-- VIEW: derive optimistic cart from server data + concurrentSubmissions, then render.


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app _ _ =
    let
        pendingItems : Dict String Int
        pendingItems =
            app.concurrentSubmissions
                |> Dict.values
                |> List.filter
                    (\pending ->
                        case pending.status of
                            Pages.ConcurrentSubmission.Complete _ ->
                                False

                            _ ->
                                True
                    )
                |> List.filterMap
                    (\pending ->
                        case Form.Handler.run pending.payload.fields formHandlers of
                            Form.Valid (SetQuantity coffeeId qty) ->
                                Just ( coffeeId, qty )

                            _ ->
                                Nothing
                    )
                |> Dict.fromList

        cartWithPending : Cart
        cartWithPending =
            mergePending app.data.coffees (app.data.cart |> Maybe.withDefault Dict.empty) pendingItems

        totals : Totals
        totals =
            computeTotals cartWithPending

        cartLines : List View.Coffee.ReceiptLine
        cartLines =
            app.data.coffees
                |> List.filterMap
                    (\coffee ->
                        cartWithPending
                            |> Dict.get coffee.id
                            |> Maybe.map
                                (\entry ->
                                    { coffee = coffee
                                    , qty = entry.quantity
                                    , isPending = Dict.member coffee.id pendingItems
                                    }
                                )
                    )
    in
    { title = "Blendhaus · " ++ app.data.user.name
    , body =
        [ View.Coffee.shell
            { greeting = Just app.data.user.name
            , signoutForm = Just (renderSignout app)
            , cartCount = totals.totalItems
            , active = "shop"
            }
        , View.Coffee.hero
        , Html.main_ [ Attr.class "bh-shop" ]
            [ Html.div [] (menuSections app cartWithPending pendingItems)
            , View.Coffee.cartPanel
                { lines = cartLines
                , subtotal = totals.subtotal
                , tax = totals.tax
                , total = totals.total
                , anyPending = not (Dict.isEmpty pendingItems)
                , checkout =
                    Html.a
                        [ Attr.class "bh-checkout-btn"
                        , Attr.href "/checkout"
                        , Attr.attribute "aria-disabled" (boolAttr (List.isEmpty cartLines))
                        ]
                        [ Html.span [] [ Html.text "Checkout" ]
                        , Html.span [ Attr.class "arr" ] [ Html.text "→" ]
                        ]
                }
            ]
        , View.Coffee.infoStrip
        ]
    }


renderSignout : App Data ActionData RouteParams -> Html (PagesMsg Msg)
renderSignout app =
    signoutForm
        |> Pages.Form.renderHtml []
            (Form.options "signout" |> Pages.Form.withConcurrent)
            app


menuSections : App Data ActionData RouteParams -> Cart -> Dict String Int -> List (Html (PagesMsg Msg))
menuSections app cart pendingItems =
    app.data.coffees
        |> groupBySection
        |> List.indexedMap
            (\sectionIndex ( section, coffees ) ->
                Html.section []
                    [ View.Coffee.sectionHead
                        { name = section, ix = sectionIndex + 1, count = List.length coffees }
                    , Html.ul [ Attr.class "bh-grid" ]
                        (List.map (renderCard app cart pendingItems) coffees)
                    ]
            )


renderCard : App Data ActionData RouteParams -> Cart -> Dict String Int -> Coffee -> Html (PagesMsg Msg)
renderCard app cart pendingItems coffee =
    let
        qty =
            cart
                |> Dict.get coffee.id
                |> Maybe.map .quantity
                |> Maybe.withDefault 0
    in
    View.Coffee.productCard
        { coffee = coffee
        , qty = qty
        , isPending = Dict.member coffee.id pendingItems
        , decrement = renderQuantity app coffee qty Decrement
        , increment = renderQuantity app coffee qty Increment
        }


renderQuantity : App Data ActionData RouteParams -> Coffee -> Int -> QuantityChange -> Html (PagesMsg Msg)
renderQuantity app coffee qty change =
    let
        prefix =
            case change of
                Increment ->
                    "increment-"

                Decrement ->
                    "decrement-"
    in
    setQuantityForm
        |> Pages.Form.renderHtml []
            (Form.options (prefix ++ coffee.id)
                |> Pages.Form.withConcurrent
                |> Form.withInput ( qty, change, coffee )
            )
            app



-- HELPERS (intentionally tucked at the bottom so the demo flow reads top-down)


type alias Totals =
    { totalItems : Int, subtotal : Int, tax : Int, total : Int }


computeTotals : Cart -> Totals
computeTotals cart =
    let
        ( items, subtotal ) =
            cart
                |> Dict.foldl
                    (\_ entry ( i, s ) -> ( i + entry.quantity, s + entry.quantity * entry.pricePerItem ))
                    ( 0, 0 )

        tax =
            (subtotal * 8) // 100
    in
    { totalItems = items, subtotal = subtotal, tax = tax, total = subtotal + tax }


mergePending : List Coffee -> Cart -> Dict String Int -> Cart
mergePending coffees serverCart pendingItems =
    let
        priceFor coffeeId =
            coffees
                |> List.filter (\c -> c.id == coffeeId)
                |> List.head
                |> Maybe.map .price
                |> Maybe.withDefault 0

        updated =
            serverCart
                |> Dict.map
                    (\itemId entry ->
                        case Dict.get itemId pendingItems of
                            Just qty ->
                                { entry | quantity = qty }

                            Nothing ->
                                entry
                    )

        newPending =
            pendingItems
                |> Dict.filter (\itemId _ -> not (Dict.member itemId serverCart))
                |> Dict.map (\itemId qty -> { quantity = qty, pricePerItem = priceFor itemId })
    in
    Dict.union updated newPending
        |> Dict.filter (\_ entry -> entry.quantity > 0)


groupBySection : List Coffee -> List ( String, List Coffee )
groupBySection coffees =
    let
        sectionsInOrder =
            coffees
                |> List.foldl
                    (\c acc ->
                        if List.member c.section acc then
                            acc

                        else
                            acc ++ [ c.section ]
                    )
                    []
    in
    sectionsInOrder
        |> List.map (\sec -> ( sec, List.filter (\c -> c.section == sec) coffees ))


boolAttr : Bool -> String
boolAttr b =
    if b then
        "true"

    else
        "false"
