module ApiHandler exposing (..)

import Regex


withRoutes : Handler Response (List (List String)) -> List String
withRoutes (Handler pattern handler toString dynamicSegments) =
    dynamicSegments
        |> List.map toString



--|> List.map (\value -> toString value)


tryMatch : String -> Handler Response b -> Maybe Response
tryMatch path (Handler pattern handler toString dynamicSegments) =
    let
        matches =
            Regex.find
                (Regex.fromString (pattern |> Debug.log "pattern")
                    |> Maybe.withDefault Regex.never
                )
                path
                |> List.concatMap .submatches
                |> List.filterMap identity
    in
    handler matches
        |> Just



--exampleHandler : Handler Response
--exampleHandler =
--    succeed
--        (\userId ->
--            { body = "Data for user " ++ userId }
--        )
--        |> captureSegment


type Handler a b
    = Handler String (List String -> a) (List String -> String) b


type alias Response =
    { body : String }


succeed : a -> ((b -> List String) -> List (List String)) -> Handler a ((b -> List String) -> List (List String))
succeed a buildTimePaths =
    Handler "" (\args -> a) (\_ -> "") buildTimePaths



--handle : (a -> Response) -> Handler a b -> Handler response b
--handle function handler =
--    Debug.todo ""


literalSegment : String -> Handler a b -> Handler a b
literalSegment segment (Handler pattern handler toString dynamicSegments) =
    Handler (pattern ++ segment) handler (\values -> toString values ++ segment) dynamicSegments


slash : Handler a b -> Handler a b
slash (Handler pattern handler toString dynamicSegments) =
    Handler (pattern ++ "/") handler (\arg -> toString arg ++ "/") dynamicSegments


captureSegment : Handler (String -> a) ((String -> List String) -> List (List String)) -> Handler a (List (List String))
captureSegment (Handler pattern previousHandler toString dynamicSegments) =
    Handler (pattern ++ "(.*)")
        (\matches ->
            case matches of
                first :: rest ->
                    previousHandler rest first

                _ ->
                    Debug.todo "Expected non-empty list"
        )
        (\s ->
            case s of
                first :: rest ->
                    toString s ++ first

                _ ->
                    ""
        )
        (dynamicSegments (\string -> [ string ]))


captureRest : Handler (List String -> a) b -> Handler a b
captureRest previousHandler =
    Debug.todo ""
