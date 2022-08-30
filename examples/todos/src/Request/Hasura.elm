module Request.Hasura exposing (dataSource, mutationDataSource)

import DataSource exposing (DataSource)
import DataSource.Env
import DataSource.Http
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Encode as Encode


dataSource : SelectionSet value RootQuery -> DataSource error value
dataSource selectionSet =
    DataSource.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> DataSource.andThen
            (\hasuraSecret ->
                DataSource.Http.uncachedRequest
                    { url = hasuraUrl
                    , method = "POST"
                    , headers = [ ( "x-hasura-admin-secret", hasuraSecret ) ]
                    , body =
                        DataSource.Http.jsonBody
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
                        |> DataSource.Http.expectJson
                    )
            )


mutationDataSource : SelectionSet value RootMutation -> DataSource error value
mutationDataSource selectionSet =
    DataSource.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> DataSource.andThen
            (\hasuraSecret ->
                DataSource.Http.uncachedRequest
                    { url = hasuraUrl
                    , method = "POST"
                    , headers = [ ( "x-hasura-admin-secret", hasuraSecret ) ]
                    , body =
                        DataSource.Http.jsonBody
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
                        |> DataSource.Http.expectJson
                    )
            )


hasuraUrl : String
hasuraUrl =
    "https://elm-pages-todos.hasura.app/v1/graphql"
