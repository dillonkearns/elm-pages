module Data.Todo exposing (..)

import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.Sessions
import Api.Object.Todos
import Api.Object.Users
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)


type alias Todo =
    { description : String
    , completed : Bool
    , id : Uuid
    }


findAllBySession : String -> SelectionSet (Maybe (List Todo)) RootQuery
findAllBySession sessionId =
    Api.Query.sessions_by_pk { id = Uuid sessionId }
        (Api.Object.Sessions.user
            (Api.Object.Users.todos identity
                todoSelection
            )
        )


todoSelection : SelectionSet Todo Api.Object.Todos
todoSelection =
    SelectionSet.map3 Todo
        Api.Object.Todos.title
        Api.Object.Todos.complete
        Api.Object.Todos.id


create : Uuid -> String -> SelectionSet Uuid RootMutation
create userId title =
    Api.Mutation.insert_todos_one identity
        { object =
            Api.InputObject.buildTodos_insert_input
                (\opts ->
                    { opts
                        | title = Present title
                        , user_id = Present userId
                    }
                )
        }
        Api.Object.Todos.id
        |> SelectionSet.nonNullOrFail
