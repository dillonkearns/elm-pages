module Data.Smoothies exposing (Smoothie, all, create, delete, find, update)

import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.Products
import Api.Query
import Api.Scalar exposing (Uuid(..))
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Request.Hasura


type alias Smoothie =
    { name : String
    , id : String
    , description : String
    , price : Int
    , unsplashImage : String
    }


selection : SelectionSet (List Smoothie) RootQuery
selection =
    Api.Query.products identity singleSelection


singleSelection : SelectionSet Smoothie Api.Object.Products
singleSelection =
    SelectionSet.map5 Smoothie
        Api.Object.Products.name
        (Api.Object.Products.id |> SelectionSet.map (\(Uuid raw) -> raw))
        Api.Object.Products.description
        Api.Object.Products.price
        Api.Object.Products.unsplash_image_id


all : BackendTask FatalError (List Smoothie)
all =
    Request.Hasura.backendTask selection


find : String -> BackendTask FatalError (Maybe Smoothie)
find id =
    Api.Query.products_by_pk
        { id = Uuid id
        }
        singleSelection
        |> Request.Hasura.backendTask


create : { name : String, description : String, price : Int, imageUrl : String } -> BackendTask FatalError ()
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
        |> Request.Hasura.mutationBackendTask


update : String -> { name : String, description : String, price : Int, imageUrl : String } -> BackendTask FatalError ()
update id item =
    Api.Mutation.update_products_by_pk
        (\_ ->
            { inc_ = Absent
            , set_ =
                Api.InputObject.buildProducts_set_input
                    (\opts ->
                        { opts
                            | name = Present item.name
                            , description = Present item.description
                            , price = Present item.price
                            , unsplash_image_id = Present item.imageUrl
                        }
                    )
                    |> Present
            }
        )
        { pk_columns =
            Api.InputObject.buildProducts_pk_columns_input
                { id = Uuid id }
        }
        SelectionSet.empty
        |> SelectionSet.nonNullOrFail
        |> Request.Hasura.mutationBackendTask


delete : String -> BackendTask FatalError ()
delete id =
    Api.Mutation.delete_products_by_pk
        { id = Uuid id }
        SelectionSet.empty
        |> SelectionSet.nonNullOrFail
        |> Request.Hasura.mutationBackendTask
