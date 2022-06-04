module Data.User exposing (User, selection, updateUser)

import Api.InputObject
import Api.Mutation
import Api.Object.Users
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)


type alias User =
    { name : String
    , username : String
    }


selection : String -> SelectionSet User RootQuery
selection userId =
    Api.Query.users_by_pk { id = Uuid userId }
        (SelectionSet.map2 User
            Api.Object.Users.name
            Api.Object.Users.username
        )
        |> SelectionSet.nonNullOrFail


updateUser : { userId : Uuid, name : String } -> SelectionSet () Graphql.Operation.RootMutation
updateUser { userId, name } =
    Api.Mutation.update_users_by_pk
        (\_ ->
            { set_ =
                Present
                    (Api.InputObject.buildUsers_set_input
                        (\optionals ->
                            { optionals
                                | name = Present name
                            }
                        )
                    )
            }
        )
        { pk_columns =
            { id = userId }
        }
        SelectionSet.empty
        |> SelectionSet.nonNullOrFail
