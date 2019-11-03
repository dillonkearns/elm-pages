module Json.Decode.Exploration.Located exposing (Located(..), toString, map)

{-| A type that gives one or more pieces of information, tagged with a path
through a datastructure with fields and indices.

Most importantly, it is used for both `Warnings` and `Errors` in `Json.Decode.Exploration`.

@docs Located, toString, map

-}

import List.Nonempty as Nonempty exposing (Nonempty(..))


{-| -}
type Located a
    = InField String (Nonempty (Located a))
    | AtIndex Int (Nonempty (Located a))
    | Here a


{-| Allows turning a non-empty list of `Located a` into a flat list of human
readable strings, provided we have a way to turn an `a` into some lines of text.

Each string represents a line. This allows arbitrary indentation by mapping over
the lines and prepending some whitespace.

-}
toString : (a -> List String) -> Nonempty (Located a) -> List String
toString itemToString locatedItems =
    locatedItems
        |> gather ""
        |> List.map (\( x, vals ) -> render itemToString x vals)
        |> intercalate ""


{-| -}
map : (a -> b) -> Located a -> Located b
map op located =
    case located of
        InField f val ->
            InField f <| Nonempty.map (map op) val

        AtIndex i val ->
            AtIndex i <| Nonempty.map (map op) val

        Here v ->
            Here (op v)


intercalate : a -> List (List a) -> List a
intercalate sep lists =
    lists |> List.intersperse [ sep ] |> List.concat


render : (a -> List String) -> String -> List a -> List String
render itemToString path errors =
    let
        formattedErrors : List String
        formattedErrors =
            List.concatMap itemToString errors
                |> List.map indent
    in
    if String.isEmpty path then
        formattedErrors

    else
        ("At path " ++ path) :: "" :: formattedErrors


indent : String -> String
indent =
    (++) "  "


flatten : Located a -> List ( String, List a )
flatten located =
    case located of
        Here v ->
            [ ( "", [ v ] ) ]

        InField s vals ->
            gather ("/" ++ s) vals

        AtIndex i vals ->
            gather ("/" ++ String.fromInt i) vals


gather : String -> Nonempty (Located a) -> List ( String, List a )
gather prefix (Nonempty first rest) =
    List.concatMap flatten (first :: rest)
        |> List.map (Tuple.mapFirst ((++) prefix))
