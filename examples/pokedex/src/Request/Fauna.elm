module Request.Fauna exposing (backendTask, mutationBackendTask)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Encode as Encode


backendTask : String -> SelectionSet value RootQuery -> BackendTask value
backendTask timeStamp selectionSet =
    BackendTask.Http.request
        { url =
            faunaUrl
                -- for now, this timestamp invalidates the dev server cache
                -- it would be helpful to have a way to mark a BackendTask as uncached. Maybe only allow
                -- from server-rendered pages?
                ++ "?time="
                ++ timeStamp
        , method = "POST"
        , headers = [ ( "authorization", faunaAuthValue ) ]
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "query"
                      , selectionSet
                            |> Graphql.Document.serializeQuery
                            |> Encode.string
                      )
                    ]
                )
        }
        (selectionSet
            |> Graphql.Document.decoder
            |> BackendTask.Http.expectJson
        )


mutationBackendTask : String -> SelectionSet value RootMutation -> BackendTask value
mutationBackendTask timeStamp selectionSet =
    BackendTask.Http.request
        { url = faunaUrl ++ "?time=" ++ timeStamp
        , method = "POST"
        , headers = [ ( "authorization", faunaAuthValue ) ]
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "query"
                      , selectionSet
                            |> Graphql.Document.serializeMutation
                            |> Encode.string
                      )
                    ]
                )
        }
        (selectionSet
            |> Graphql.Document.decoder
            |> BackendTask.Http.expectJson
        )


faunaUrl : String
faunaUrl =
    "https://graphql.us.fauna.com/graphql"


faunaAuthValue : String
faunaAuthValue =
    "Bearer fnAEdqJ_JdAAST7wRrjZj7NKSw-vCfE9_W8RyshZ"
