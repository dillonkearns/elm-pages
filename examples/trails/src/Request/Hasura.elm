module Request.Hasura exposing (dataSource, mutationDataSource)

import DataSource exposing (DataSource)
import DataSource.Env
import DataSource.Http
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Encode as Encode


dataSource : String -> SelectionSet value RootQuery -> DataSource value
dataSource timeStamp selectionSet =
    DataSource.Env.expect "TRAILS_HASURA_SECRET"
        |> DataSource.andThen
            (\hasuraSecret ->
                DataSource.Http.request
                    { url =
                        hasuraUrl
                            -- for now, this timestamp invalidates the dev server cache
                            -- it would be helpful to have a way to mark a DataSource as uncached. Maybe only allow
                            -- from server-rendered pages?
                            ++ "?time="
                            ++ timeStamp
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


mutationDataSource : String -> SelectionSet value RootMutation -> DataSource value
mutationDataSource timeStamp selectionSet =
    DataSource.Env.expect "TRAILS_HASURA_SECRET"
        |> DataSource.andThen
            (\hasuraSecret ->
                DataSource.Http.request
                    { url = hasuraUrl ++ "?time=" ++ timeStamp
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
    "https://striking-mutt-82.hasura.app/v1/graphql"
