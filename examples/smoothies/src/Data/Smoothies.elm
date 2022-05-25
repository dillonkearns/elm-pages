module Data.Smoothies exposing (Smoothie, selection)

import Api.Object.Products
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Graphql.Operation exposing (RootQuery)
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)


type alias Smoothie =
    { name : String
    , id : Uuid
    , description : String
    , price : Int
    , unsplashImage : String
    }


selection : SelectionSet (List Smoothie) RootQuery
selection =
    Api.Query.products identity
        (SelectionSet.map5 Smoothie
            Api.Object.Products.name
            Api.Object.Products.id
            Api.Object.Products.description
            Api.Object.Products.price
            Api.Object.Products.unsplash_image_id
        )
