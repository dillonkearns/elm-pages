module Elm.Extra exposing (topLevelValue)

import Elm
import Elm.Declare


topLevelValue :
    String
    -> Elm.Expression
    ->
        { declaration : Elm.Declaration
        , reference : Elm.Expression
        , referenceFrom : List String -> Elm.Expression
        }
topLevelValue name expression =
    let
        declaration_ :
            { declaration : Elm.Declaration
            , call : List Elm.Expression -> Elm.Expression
            , callFrom : List String -> List Elm.Expression -> Elm.Expression
            }
        declaration_ =
            Elm.Declare.function name
                []
                (\_ -> expression)
    in
    { declaration = declaration_.declaration
    , reference = declaration_.call []
    , referenceFrom = \from -> declaration_.callFrom from []
    }
