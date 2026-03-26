module Request.Hasura exposing (backendTask, graphqlRequest, mutationBackendTask)

import BackendTask exposing (BackendTask)
import BackendTask.Env
import BackendTask.Http
import FatalError exposing (FatalError)
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Decode as Decode
import Json.Encode as Encode


backendTask : SelectionSet value RootQuery -> BackendTask FatalError value
backendTask selectionSet =
    BackendTask.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\hasuraSecret ->
                BackendTask.Http.request
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
                    , retries = Nothing
                    , timeoutInMs = Nothing
                    }
                    (selectionSet
                        |> Graphql.Document.decoder
                        |> BackendTask.Http.expectJson
                    )
                    |> BackendTask.allowFatal
            )


mutationBackendTask : SelectionSet value RootMutation -> BackendTask FatalError value
mutationBackendTask selectionSet =
    BackendTask.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\hasuraSecret ->
                BackendTask.Http.request
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
                    , retries = Nothing
                    , timeoutInMs = Nothing
                    }
                    (selectionSet
                        |> Graphql.Document.decoder
                        |> BackendTask.Http.expectJson
                    )
                    |> BackendTask.allowFatal
            )


graphqlRequest :
    { query : String
    , variables : List ( String, Encode.Value )
    , decoder : Decode.Decoder value
    }
    -> BackendTask FatalError value
graphqlRequest { query, variables, decoder } =
    BackendTask.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\hasuraSecret ->
                BackendTask.Http.request
                    { url = hasuraUrl
                    , method = "POST"
                    , headers = [ ( "x-hasura-admin-secret", hasuraSecret ) ]
                    , body =
                        BackendTask.Http.jsonBody
                            (Encode.object
                                [ ( "query", Encode.string query )
                                , ( "variables", Encode.object variables )
                                ]
                            )
                    , retries = Nothing
                    , timeoutInMs = Nothing
                    }
                    (decoder |> BackendTask.Http.expectJson)
                    |> BackendTask.allowFatal
            )


hasuraUrl : String
hasuraUrl =
    "https://loyal-mammal-32.hasura.app/v1/graphql"
