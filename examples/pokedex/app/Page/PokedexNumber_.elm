module Page.PokedexNumber_ exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes exposing (src)
import Json.Decode as Decode
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { pokedexNumber : String }


page : Page RouteParams Data
page =
    Page.preRenderWithFallback
        { head = head
        , pages = pages
        , data = data
        }
        |> Page.buildNoState { view = view }


pages : DataSource (List RouteParams)
pages =
    DataSource.succeed []


data : RouteParams -> DataSource (Response Data)
data { pokedexNumber } =
    let
        asNumber : Int
        asNumber =
            String.toInt pokedexNumber |> Maybe.withDefault -1
    in
    if asNumber < 1 then
        notFoundResponse "Pokedex numbers must be 1 or greater."

    else if asNumber > 898 && asNumber < 10001 || asNumber > 10194 then
        notFoundResponse "The pokedex is empty in that range."

    else
        DataSource.map2 Data
            (DataSource.Http.get "https://elm-pages-pokedex.netlify.app/.netlify/functions/time"
                Decode.string
            )
            (DataSource.Http.get ("https://pokeapi.co/api/v2/pokemon/" ++ pokedexNumber)
                (Decode.map2 Pokemon
                    (Decode.field "forms" (Decode.index 0 (Decode.field "name" Decode.string)))
                    (Decode.field "types" (Decode.list (Decode.field "type" (Decode.field "name" Decode.string))))
                )
            )
            |> DataSource.map Response.render


notFoundResponse : String -> DataSource (Response Data)
notFoundResponse message =
    Response.plainText
        ("Not found.\n\n" ++ message)
        |> Response.withStatusCode 404
        |> DataSource.succeed


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
        , siteName = "elm-pages Pokedex"
        , image =
            { url = static.routeParams |> pokemonImage |> Pages.Url.external
            , alt = static.data.pokemon.name
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title =
            "Pokedex #"
                ++ static.routeParams.pokedexNumber
                ++ " "
                ++ static.data.pokemon.name
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
            [ static.routeParams |> pokemonImage |> src
            ]
            []
        , p []
            [ text static.data.time
            ]
        ]
    }


pokemonImage : RouteParams -> String
pokemonImage routeParams =
    "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/" ++ routeParams.pokedexNumber ++ ".png"
