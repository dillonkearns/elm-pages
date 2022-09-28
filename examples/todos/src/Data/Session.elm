module Data.Session exposing (..)

import Api.Enum.Users_constraint
import Api.Enum.Users_update_column
import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.Sessions
import Api.Object.Users
import Api.Query
import Api.Scalar exposing (Timestamptz(..), Uuid(..))
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Iso8601
import Time


findOrCreateUser : String -> SelectionSet Uuid RootMutation
findOrCreateUser emailAddress =
    Api.Mutation.insert_users_one
        (\_ ->
            { on_conflict =
                Present
                    (Api.InputObject.buildUsers_on_conflict
                        { constraint = Api.Enum.Users_constraint.Users_email_key
                        , update_columns = [ Api.Enum.Users_update_column.Email ]
                        }
                        (\opts -> opts)
                    )
            }
        )
        { object =
            Api.InputObject.buildUsers_insert_input
                (\opts ->
                    { opts | email = Present emailAddress }
                )
        }
        Api.Object.Users.id
        |> SelectionSet.nonNullOrFail


create : Time.Posix -> Uuid -> SelectionSet Uuid RootMutation
create expiresAt userId =
    Api.Mutation.insert_sessions_one
        identity
        { object =
            Api.InputObject.buildSessions_insert_input
                (\opts ->
                    { opts
                        | expires_at =
                            expiresAt
                                |> Iso8601.fromTime
                                |> Timestamptz
                                |> Present
                        , user_id = Present userId
                    }
                )
        }
        Api.Object.Sessions.id
        |> SelectionSet.nonNullOrFail


type alias Session =
    { emailAddress : String
    , id : Uuid
    }


get : String -> SelectionSet (Maybe Session) RootQuery
get sessionId =
    Api.Query.sessions_by_pk { id = Uuid sessionId }
        (Api.Object.Sessions.user
            (SelectionSet.map2 Session
                Api.Object.Users.email
                Api.Object.Users.id
            )
        )
