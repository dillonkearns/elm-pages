module Page.PokedexNumber_ exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes exposing (src)
import OptimizedDecoder as Decode
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Secrets
import Shared
import View exposing (View)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { pokedexnumber : String }


page : Page RouteParams Data
page =
    Page.prerenderedRouteWithFallback
        { head = head
        , routes = routes
        , data = data
        , handleFallback =
            \{ pokedexnumber } ->
                let
                    asNumber : Int
                    asNumber =
                        String.toInt pokedexnumber |> Maybe.withDefault -1
                in
                DataSource.succeed
                    (asNumber > 0 && asNumber < 150)
        }
        |> Page.buildNoState { view = view }


routes : DataSource (List RouteParams)
routes =
    DataSource.succeed []


data : RouteParams -> DataSource Data
data routeParams =
    DataSource.map2 Data
        (DataSource.Http.get (Secrets.succeed "https://elm-pages-pokedex.netlify.app/.netlify/functions/time")
            Decode.string
        )
        (DataSource.Http.get (Secrets.succeed ("https://pokeapi.co/api/v2/pokemon/" ++ routeParams.pokedexnumber))
            (Decode.map2 Pokemon
                (Decode.field "forms" (Decode.index 0 (Decode.field "name" Decode.string)))
                (Decode.field "types" (Decode.list (Decode.field "type" (Decode.field "name" Decode.string))))
            )
        )


type alias Pokemon =
    { name : String
    , abilities : List String
    }


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias Data =
    { time : String
    , pokemon : Pokemon
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = static.data.pokemon.name
    , body =
        [ h1 []
            [ text static.data.pokemon.name
            ]
        , text (static.data.pokemon.abilities |> String.join ", ")
        , img
            [ src <| "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/" ++ static.routeParams.pokedexnumber ++ ".png"
            ]
            []
        , p []
            [ text static.data.time
            ]
        ]
    }
