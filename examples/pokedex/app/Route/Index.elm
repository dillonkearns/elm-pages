module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import BackendTask.Http
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (..)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { pokemon : List String, envValue : Maybe String }


type alias ActionData =
    {}


data : BackendTask FatalError Data
data =
    BackendTask.map2 Data
        (BackendTask.Http.getJson
            "https://pokeapi.co/api/v2/pokemon/?limit=100&offset=0"
            (Decode.field "results"
                (Decode.list (Decode.field "name" Decode.string))
            )
            |> BackendTask.throw
        )
        (Env.get "HELLO")


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages Pokedex"
        , image =
            { url = Pages.Url.external ""
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "This is a simple app to showcase server-rendering with elm-pages."
        , locale = Nothing
        , title = "Elm Pages Pokedex Example"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "Pokedex"
    , body =
        [ ul []
            (List.indexedMap
                (\index name ->
                    let
                        pokedexNumber =
                            index + 1
                    in
                    li []
                        [ Route.PokedexNumber_ { pokedexNumber = String.fromInt pokedexNumber }
                            |> Route.link [] [ text name ]
                        ]
                )
                static.data.pokemon
            )
        ]
    }
