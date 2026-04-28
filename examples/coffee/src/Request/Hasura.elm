module Request.Hasura exposing (backendTask, graphqlRequest, mutationBackendTask)

{-| Pre-baked Hasura helpers.

Each function reads the `HASURA_ADMIN_SECRET` env var on the server and POSTs
to the GraphQL endpoint. There is no client surface — the secret never leaves
the server.

-}

import BackendTask exposing (BackendTask)
import BackendTask.Env
import BackendTask.Http
import FatalError exposing (FatalError)
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Decode as Decode
import Json.Encode as Encode


hasuraUrl : String
hasuraUrl =
    "https://loyal-mammal-32.hasura.app/v1/graphql"


backendTask : SelectionSet value RootQuery -> BackendTask FatalError value
backendTask selectionSet =
    withSecret
        (\secret ->
            postJson secret
                [ ( "query", Encode.string (Graphql.Document.serializeQuery selectionSet) ) ]
                (Graphql.Document.decoder selectionSet)
        )


mutationBackendTask : SelectionSet value RootMutation -> BackendTask FatalError value
mutationBackendTask selectionSet =
    withSecret
        (\secret ->
            postJson secret
                [ ( "query", Encode.string (Graphql.Document.serializeMutation selectionSet) ) ]
                (Graphql.Document.decoder selectionSet)
        )


graphqlRequest :
    { query : String
    , variables : List ( String, Encode.Value )
    , decoder : Decode.Decoder value
    }
    -> BackendTask FatalError value
graphqlRequest { query, variables, decoder } =
    withSecret
        (\secret ->
            postJson secret
                [ ( "query", Encode.string query )
                , ( "variables", Encode.object variables )
                ]
                decoder
        )


withSecret : (String -> BackendTask FatalError a) -> BackendTask FatalError a
withSecret toTask =
    BackendTask.Env.expect "HASURA_ADMIN_SECRET"
        |> BackendTask.allowFatal
        |> BackendTask.andThen toTask


postJson : String -> List ( String, Encode.Value ) -> Decode.Decoder a -> BackendTask FatalError a
postJson secret body decoder =
    BackendTask.Http.request
        { url = hasuraUrl
        , method = "POST"
        , headers = [ ( "x-hasura-admin-secret", secret ) ]
        , body = BackendTask.Http.jsonBody (Encode.object body)
        , retries = Nothing
        , timeoutInMs = Nothing
        }
        (BackendTask.Http.expectJson decoder)
        |> BackendTask.allowFatal
