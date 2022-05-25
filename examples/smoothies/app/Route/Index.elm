module Route.Index exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Cart as Cart exposing (Cart)
import Data.Smoothies exposing (Smoothie)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Icon
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Seo.Common
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


type alias Data =
    {}


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


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.Common.tags


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Response.render {}
        |> DataSource.succeed
        |> Request.succeed


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Response.render {}
        |> DataSource.succeed
        |> Request.succeed


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Ctrl-R Smoothies"
    , body =
        let
            totals : { totalItems : Int, totalPrice : Int }
            totals =
                todoCart
                    |> Dict.foldl
                        (\_ { quantity, pricePerItem } soFar ->
                            { soFar
                                | totalItems = soFar.totalItems + quantity
                                , totalPrice = soFar.totalPrice + (quantity * pricePerItem)
                            }
                        )
                        { totalItems = 0, totalPrice = 0 }
        in
        [ Html.p []
            [ Html.text <| "Welcome " ++ todoUserName ++ "!"
            , Html.div
                []
                [ Html.button [] [ Html.text "Sign out TODO" ] ]
            ]
        , cartView totals
        , todoSmoothies
            |> List.map
                (productView todoCart)
            |> Html.ul []
        ]
    }


todoCart : Cart
todoCart =
    Dict.fromList
        [ ( "1", { quantity = 2, pricePerItem = 123 } )
        ]


todoSmoothies : List Smoothie
todoSmoothies =
    [ { name = "TODO name 1"
      , id = Uuid "1"
      , description = "TODO description 1"
      , price = 123
      , unsplashImage = "https://images.unsplash.com/photo-1622428051717-dcd8412959de"
      }
    , { name = "TODO name 1"
      , id = Uuid "2"
      , description = "TODO description 2"
      , price = 456
      , unsplashImage = "https://images.unsplash.com/photo-1622428051717-dcd8412959de"
      }
    ]


todoUserName =
    "TODO USER NAME"


cartView : { totalItems : Int, totalPrice : Int } -> Html msg
cartView totals =
    Html.button [ Attr.class "checkout" ]
        [ Html.span [ Attr.class "icon" ] [ Icon.cart ]
        , Html.text <| " Checkout (" ++ String.fromInt totals.totalItems ++ ") $" ++ String.fromInt totals.totalPrice
        ]


uuidToString : Uuid -> String
uuidToString (Uuid id) =
    id


productView : Dict String Cart.CartEntry -> Smoothie -> Html (Pages.Msg.Msg msg)
productView cart item =
    let
        quantityInCart : Int
        quantityInCart =
            cart
                |> Dict.get (uuidToString item.id)
                |> Maybe.map .quantity
                |> Maybe.withDefault 0
    in
    Html.li [ Attr.class "item" ]
        [ Html.div []
            [ Html.h3 [] [ Html.text item.name ]
            , Html.p [] [ Html.text item.description ]
            , Html.p [] [ "$" ++ String.fromInt item.price |> Html.text ]
            ]
        , Html.div
            []
            [ Html.button [] [ Html.text "-" ]
            , Html.p [] [ quantityInCart |> String.fromInt |> Html.text ]
            , Html.button [] [ Html.text "+" ]
            ]
        , Html.div []
            [ Html.img
                [ Attr.src (item.unsplashImage ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903") ]
                []
            ]
        ]
