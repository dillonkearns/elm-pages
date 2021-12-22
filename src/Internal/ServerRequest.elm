module Internal.ServerRequest exposing (IsAvailable(..))

{-| -}


{-| This will be passed in wherever it's possible to access the DataSource.ServerRequest, like in a serverless request. This data, like the query params or incoming request headers,
do not exist for pre-rendered pages since they are not responding to a user request. They are built in advance. This value ensures that the compiler will make sure you can only use
the DataSource.ServerRequest API when it will actually be there for you to use.
-}
type IsAvailable
    = IsAvailable
