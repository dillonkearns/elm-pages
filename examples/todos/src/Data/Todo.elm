module Data.Todo exposing (..)

import Api.Object
import Api.Object.Sessions
import Api.Object.Todos
import Api.Object.Users
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Graphql.Operation exposing (RootQuery)
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
