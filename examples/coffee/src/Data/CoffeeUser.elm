module Data.CoffeeUser exposing (User, find, login, signup)

{-| Coffee user — re-uses the shared `users` table.

Pre-baked: login does a username + password-hash lookup; signup inserts
a new user. Both return the user id so the route can drop it into the session.

-}

import Api.InputObject
import Api.Mutation
import Api.Object.Users
import Api.Query
import Api.Scalar exposing (Uuid(..))
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet
import Request.Hasura


type alias User =
    { name : String
    , username : String
    }


find : String -> BackendTask FatalError User
find userId =
    Api.Query.users_by_pk { id = Uuid userId }
        (SelectionSet.map2 User
            Api.Object.Users.name
            Api.Object.Users.username
        )
        |> SelectionSet.nonNullOrFail
        |> Request.Hasura.backendTask


login : { username : String, expectedPasswordHash : String } -> BackendTask FatalError (Maybe String)
login { username, expectedPasswordHash } =
    Api.Query.users
        (\opts ->
            { opts
                | where_ =
                    Present
                        (Api.InputObject.buildUsers_bool_exp
                            (\inner ->
                                { inner
                                    | username = Present (eq username)
                                    , password_hash = Present (eq expectedPasswordHash)
                                }
                            )
                        )
            }
        )
        Api.Object.Users.id
        |> SelectionSet.map (List.head >> Maybe.map (\(Uuid raw) -> raw))
        |> Request.Hasura.backendTask


signup : { name : String, username : String, passwordHash : String } -> BackendTask FatalError (Maybe String)
signup { name, username, passwordHash } =
    Api.Mutation.insert_users_one identity
        { object =
            Api.InputObject.buildUsers_insert_input
                (\opts ->
                    { opts
                        | name = Present name
                        , username = Present username
                        , password_hash = Present passwordHash
                    }
                )
        }
        Api.Object.Users.id
        |> SelectionSet.map (Maybe.map (\(Uuid raw) -> raw))
        |> Request.Hasura.mutationBackendTask


eq : String -> Api.InputObject.String_comparison_exp
eq str =
    Api.InputObject.buildString_comparison_exp (\opt -> { opt | eq_ = Present str })
