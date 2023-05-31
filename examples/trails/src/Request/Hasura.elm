module Request.Hasura exposing (backendTask, mutationBackendTask)

import BackendTask exposing (BackendTask)
import BackendTask.Env
import BackendTask.Http
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Encode as Encode


backendTask : String -> SelectionSet value RootQuery -> BackendTask value
backendTask timeStamp selectionSet =
    BackendTask.Env.expect "TRAILS_HASURA_SECRET"
        |> BackendTask.andThen
            (\hasuraSecret ->
                BackendTask.Http.request
                    { url =
                        hasuraUrl
                            -- for now, this timestamp invalidates the dev server cache
                            -- it would be helpful to have a way to mark a BackendTask as uncached. Maybe only allow
                            -- from server-rendered pages?
                            ++ "?time="
                            ++ timeStamp
                    , method = "POST"
                    , headers = [ ( "x-hasura-admin-secret", hasuraSecret ) ]
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
            )


mutationBackendTask : String -> SelectionSet value RootMutation -> BackendTask value
mutationBackendTask timeStamp selectionSet =
    BackendTask.Env.expect "TRAILS_HASURA_SECRET"
        |> BackendTask.andThen
            (\hasuraSecret ->
                BackendTask.Http.request
                    { url = hasuraUrl ++ "?time=" ++ timeStamp
                    , method = "POST"
                    , headers = [ ( "x-hasura-admin-secret", hasuraSecret ) ]
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
            )


hasuraUrl : String
hasuraUrl =
    "https://striking-mutt-82.hasura.app/v1/graphql"
