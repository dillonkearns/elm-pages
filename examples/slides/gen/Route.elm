module Route exposing (..)

import Url
import Url.Parser as Parser exposing ((</>), Parser)


type Route
    = Slide__Number_ { number : String }


urlToRoute : Url.Url -> Maybe Route
urlToRoute url =
    Parser.parse (Parser.oneOf routes) url


routes : List (Parser (Route -> a) a)
routes =
    [ Parser.map (\number -> Slide__Number_ { number = number }) (Parser.s "slide" </> Parser.string)

    ]


routeToPath : Maybe Route -> List String
routeToPath maybeRoute =
    case maybeRoute of
        Nothing ->
            []
        Just (Slide__Number_ params) ->
            [ "slide", params.number ]
