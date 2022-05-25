module Request.Hasura exposing (dataSource, mutationDataSource)

import DataSource exposing (DataSource)
import DataSource.Env
import DataSource.Http
import Graphql.Document
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Encode as Encode
import Time


dataSource : Time.Posix -> SelectionSet value RootQuery -> DataSource value
dataSource requestTime selectionSet =
    DataSource.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> DataSource.andThen
            (\hasuraSecret ->
                DataSource.Http.request
                    { url =
                        hasuraUrl
                            -- for now, this timestamp invalidates the dev server cache
                            -- it would be helpful to have a way to mark a DataSource as uncached. Maybe only allow
                            -- from server-rendered pages?
                            ++ "?time="
                            ++ (requestTime |> Time.posixToMillis |> String.fromInt)
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


mutationDataSource : Time.Posix -> SelectionSet value RootMutation -> DataSource value
mutationDataSource requestTime selectionSet =
    DataSource.Env.expect "SMOOTHIES_HASURA_SECRET"
        |> DataSource.andThen
            (\hasuraSecret ->
                DataSource.Http.request
                    { url = hasuraUrl ++ "?time=" ++ (requestTime |> Time.posixToMillis |> String.fromInt)
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
    "https://smoothie-shop.hasura.app/v1/graphql"
