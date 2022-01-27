module Page.Index exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Head.Seo as Seo
import Html exposing (..)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


page : Page RouteParams Data
page =
    Page.single
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.map2 Data
        (DataSource.Http.get
            "https://pokeapi.co/api/v2/pokemon/?limit=100&offset=0"
            (Decode.field "results"
                (Decode.list (Decode.field "name" Decode.string))
            )
        )
        (env "HELLO")


env : String -> DataSource.DataSource (Maybe String)
env envVariableName =
    DataSource.Http.request
        { url = "port://env"
        , method = "GET"
        , headers = []
        , body = DataSource.Http.jsonBody (Json.Encode.string envVariableName)
        }
        (Decode.nullable Decode.string)


head :
    StaticPayload Data RouteParams
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


type alias Data =
    { pokemon : List String
    , envValue : Maybe String
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
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
                        [ Route.link (Route.PokedexNumber_ { pokedexNumber = String.fromInt pokedexNumber })
                            []
                            [ text name ]
                        ]
                )
                static.data.pokemon
            )
        , Html.text (Debug.toString static.data.envValue)
        ]
    }
