module Data.Smoothies exposing (Smoothie, create, selection)

import Api.InputObject
import Api.Mutation
import Api.Object.Products
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
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


create :
    { name : String, description : String, price : Int, imageUrl : String }
    -> SelectionSet () RootMutation
create item =
    Api.Mutation.insert_products_one identity
        { object =
            Api.InputObject.buildProducts_insert_input
                (\opts ->
                    { opts
                        | name = Present item.name
                        , description = Present item.description
                        , price = Present item.price
                        , unsplash_image_id = Present item.imageUrl
                    }
                )
        }
        SelectionSet.empty
        |> SelectionSet.nonNullOrFail
