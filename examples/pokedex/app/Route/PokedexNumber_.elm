module Route.PokedexNumber_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes exposing (src)
import Json.Decode as Decode
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { pokedexNumber : String }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRenderWithFallback
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask FatalError (List RouteParams)
pages =
    BackendTask.succeed []


data : RouteParams -> BackendTask FatalError (Response Data ErrorPage)
data { pokedexNumber } =
    let
        asNumber : Int
        asNumber =
            String.toInt pokedexNumber
                |> Maybe.withDefault -1
    in
    if asNumber < 1 then
        Response.errorPage (ErrorPage.InvalidPokedexNumber pokedexNumber)
            |> BackendTask.succeed

    else if asNumber > 898 && asNumber < 10001 || asNumber > 10194 then
        Response.errorPage (ErrorPage.MissingPokedexNumber asNumber)
            |> BackendTask.succeed

    else
        BackendTask.map2 Data
            (get "https://elm-pages-pokedex.netlify.app/.netlify/functions/time"
                Decode.string
            )
            (get ("https://pokeapi.co/api/v2/pokemon/" ++ pokedexNumber)
                (Decode.map2 Pokemon
                    (Decode.field "forms" (Decode.index 0 (Decode.field "name" Decode.string)))
                    (Decode.field "types" (Decode.list (Decode.field "type" (Decode.field "name" Decode.string))))
                )
            )
            |> BackendTask.allowFatal
            |> BackendTask.map Response.render


get : String -> Decode.Decoder value -> BackendTask { fatal : FatalError, recoverable : BackendTask.Http.Error } value
get url decoder =
    BackendTask.Http.getWithOptions
        { url = url
        , expect = BackendTask.Http.expectJson decoder
        , headers = []
        , timeoutInMs = Nothing
        , retries = Nothing
        , cachePath = Just "netlify-http-cache"
        , cacheStrategy = Nothing
        }


type alias Pokemon =
    { name : String
    , abilities : List String
    }


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages Pokedex"
        , image =
            { url = app.routeParams |> pokemonImage |> Pages.Url.external
            , alt = app.data.pokemon.name
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title =
            "Pokedex #"
                ++ app.routeParams.pokedexNumber
                ++ " "
                ++ app.data.pokemon.name
        }
        |> Seo.website


type alias Data =
    { time : String
    , pokemon : Pokemon
    }


type alias ActionData =
    {}


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = app.data.pokemon.name
    , body =
        [ h1
            []
            [ text app.data.pokemon.name
            ]
        , text (app.data.pokemon.abilities |> String.join ", ")
        , img
            [ app.routeParams |> pokemonImage |> src
            ]
            []
        , p []
            [ text app.data.time
            ]
        ]
    }


pokemonImage : RouteParams -> String
pokemonImage routeParams =
    "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/" ++ routeParams.pokedexNumber ++ ".png"
