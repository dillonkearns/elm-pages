module ErrorPage exposing (ErrorPage(..), internalError, notFound, statusCode, view)

import Html exposing (Html)


type ErrorPage
    = NotFound
    | InternalError String


notFound : ErrorPage
notFound =
    NotFound


internalError : String -> ErrorPage
internalError =
    InternalError


view : ErrorPage -> { body : Html msg, title : String }
view error =
    { body =
        Html.div []
            [ Html.text "Hi! This is a NotFound error"
            ]
    , title = "Error"
    }


statusCode : ErrorPage -> number
statusCode error =
    case error of
        NotFound ->
            404

        InternalError _ ->
            500
