module Data.Coffee exposing (Coffee, all)

{-| Coffee menu — read from the `coffees` table in Hasura.

Pre-baked ingredient: this module wraps `elm-graphql` so the demo route
just calls `Coffee.all` and gets back a `BackendTask` of menu items.

-}

import Api.Object
import Api.Object.Coffees
import Api.Query
import Api.Scalar exposing (Uuid(..))
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Request.Hasura


type alias Coffee =
    { id : String
    , name : String
    , tagline : String
    , price : Int
    , variant : String
    , section : String
    }


all : BackendTask FatalError (List Coffee)
all =
    Api.Query.coffees
        (\opts -> opts)
        coffeeSelection
        |> Request.Hasura.backendTask


coffeeSelection : SelectionSet Coffee Api.Object.Coffees
coffeeSelection =
    SelectionSet.map6 Coffee
        (Api.Object.Coffees.id |> SelectionSet.map (\(Uuid raw) -> raw))
        Api.Object.Coffees.name
        Api.Object.Coffees.tagline
        Api.Object.Coffees.price
        Api.Object.Coffees.variant
        Api.Object.Coffees.section
