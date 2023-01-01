module Request.Hasura exposing (backendTask, mutationBackendTask)

import BackendTask exposing (BackendTask)
import BackendTask.Env
import BackendTask.Http
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Encode as Encode
import Time


backendTask : SelectionSet value RootQuery -> BackendTask value
backendTask selectionSet =
    BackendTask.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> BackendTask.andThen
            (\hasuraSecret ->
                BackendTask.Http.uncachedRequest
                    { url = hasuraUrl
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


mutationBackendTask : SelectionSet value RootMutation -> BackendTask value
mutationBackendTask selectionSet =
    BackendTask.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> BackendTask.andThen
            (\hasuraSecret ->
                BackendTask.Http.uncachedRequest
                    { url = hasuraUrl
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
    "https://elm-pages-todos.hasura.app/v1/graphql"
