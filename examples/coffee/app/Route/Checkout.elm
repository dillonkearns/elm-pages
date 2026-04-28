module Route.Checkout exposing (ActionData, Data, Model, Msg, route)

{-| Bag review. Reads the same data as Index (no extra concepts), but renders
a checkout layout. "Place order" stays a stub for the demo — wiring it up is
left as an exercise.
-}

import BackendTask exposing (BackendTask)
import Data.Coffee as Coffee exposing (Coffee)
import Data.CoffeeCart as Cart
import Data.CoffeeUser as User exposing (User)
import Dict
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Validation as Validation
import Head
import Html
import Html.Attributes as Attr
import MySession
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)
import View.Coffee


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    { coffees : List Coffee
    , user : User
    , cart : Maybe Cart.Cart
    }


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


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


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action _ _ =
    BackendTask.succeed (Response.render {})


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


placeOrderForm : Form.HtmlForm String () input msg
placeOrderForm =
    Form.form
        { combine = Validation.succeed ()
        , view =
            \_ ->
                [ Html.button [ Attr.class "bh-place" ] [ Html.text "Place order →" ] ]
        }
        |> Form.hiddenKind ( "kind", "placeOrder" ) "Expected placeOrder"


view : App Data ActionData RouteParams -> Shared.Model -> View (PagesMsg Msg)
view app _ =
    let
        cart =
            app.data.cart |> Maybe.withDefault Dict.empty

        lines =
            app.data.coffees
                |> List.filterMap
                    (\coffee ->
                        cart
                            |> Dict.get coffee.id
                            |> Maybe.map
                                (\entry ->
                                    { coffee = coffee, qty = entry.quantity, isPending = False }
                                )
                    )

        subtotal =
            lines |> List.map (\l -> l.coffee.price * l.qty) |> List.sum

        tax =
            (subtotal * 8) // 100

        total =
            subtotal + tax

        cartCount =
            lines |> List.map .qty |> List.sum
    in
    { title = "Bag · Blendhaus"
    , body =
        View.Coffee.checkoutPage
            { greeting = Just app.data.user.name
            , signoutForm = Nothing
            , cartCount = cartCount
            , lines = lines
            , subtotal = subtotal
            , tax = tax
            , total = total
            , placeOrderForm =
                placeOrderForm
                    |> Pages.Form.renderHtml []
                        (Form.options "place-order")
                        app
            }
    }
