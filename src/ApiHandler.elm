module ApiHandler exposing (..)

import DataSource exposing (DataSource)
import Regex exposing (Regex)


firstMatch : String -> List (Done response) -> Maybe response
firstMatch path handlers =
    case handlers of
        [] ->
            Nothing

        first :: rest ->
            case tryMatchDone path first of
                Just response ->
                    Just response

                Nothing ->
                    firstMatch path rest


tryMatchDone : String -> Done response -> Maybe response
tryMatchDone path handler =
    let
        matches =
            path
                |> Regex.find handler.regex
                |> List.concatMap .submatches
                |> List.filterMap identity
    in
    if handler.handleRoute matches then
        handler.matchesToResponse path

    else
        Nothing


withRoutesNew :
    (constructor -> List (List String))
    -> Handler a constructor
    -> List String
withRoutesNew buildUrls (Handler pattern handler toString constructor) =
    buildUrls (constructor [])
        |> List.map toString


type alias Done response =
    { regex : Regex
    , matchesToResponse : String -> Maybe response
    , buildTimeRoutes : List String
    , handleRoute : List String -> Bool
    }


done : (constructor -> List (List String)) -> Handler response constructor -> Done response
done buildUrls (Handler pattern handler toString constructor) =
    let
        buildTimeRoutes =
            buildUrls (constructor [])
                |> List.map toString

        preBuiltMatches : List (List String)
        preBuiltMatches =
            buildUrls (constructor [])
    in
    { regex = Regex.fromString pattern |> Maybe.withDefault Regex.never
    , matchesToResponse = \path -> tryMatch path (Handler pattern handler toString constructor)
    , buildTimeRoutes = buildTimeRoutes
    , handleRoute =
        \matches ->
            preBuiltMatches
                |> List.member matches
    }



--(Handler Response constructor)


withRoutes : (constructor -> List (List String)) -> Handler a constructor -> List String
withRoutes buildUrls (Handler pattern handler toString constructor) =
    buildUrls (constructor [])
        |> List.map toString


tryMatch : String -> Handler response constructor -> Maybe response
tryMatch path (Handler pattern handler toString constructor) =
    let
        matches =
            Regex.find
                (Regex.fromString pattern
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


type Handler a constructor
    = Handler String (List String -> a) (List String -> String) (List String -> constructor)


type alias Response =
    { body : String }



--succeed : a -> ((b -> List String) -> List (List String)) -> Handler a ((b -> List String) -> List (List String))
--succeed a buildTimePaths =
--    Handler "" (\args -> a) (\_ -> "") buildTimePaths
--succeedNew :
--    a
--    ->
--        ((b -> List String)
--         -> List (List String)
--        )
--    ->
--        Handler
--            a
--            ((b -> List String)
--             -> List (List String)
--            )
--succeedNew : a -> b -> Handler a b


succeed : a -> Handler a (List String)
succeed a =
    Handler "" (\args -> a) (\_ -> "") (\list -> list)



--handle : (a -> Response) -> Handler a b -> Handler response b
--handle function handler =
--    Debug.todo ""


literal : String -> Handler a constructor -> Handler a constructor
literal segment (Handler pattern handler toString constructor) =
    Handler (pattern ++ segment) handler (\values -> toString values ++ segment) constructor


slash : Handler a constructor -> Handler a constructor
slash (Handler pattern handler toString constructor) =
    Handler (pattern ++ "/") handler (\arg -> toString arg ++ "/") constructor



--captureSegment :
--    Handler
--        (String -> a)
--        ((String -> List String)
--         -> b
--        )
--        constructor
--    ->
--        Handler
--            a
--            b
--            constructor
--captureSegment (Handler pattern previousHandler toString dynamicSegments) =
--    Handler (pattern ++ "(.*)")
--        (\matches ->
--            case matches of
--                first :: rest ->
--                    previousHandler rest first
--
--                _ ->
--                    Debug.todo "Expected non-empty list"
--        )
--        (\s ->
--            case s |> Debug.log "@@@ s" of
--                first :: rest ->
--                    toString rest ++ first
--
--                _ ->
--                    ""
--        )
--        --(dynamicSegments (\string -> [ string ]))
--        --(dynamicSegments (\_ -> []))
--        (dynamicSegments
--            (\string ->
--                [ string ]
--            )
--        )
--(Debug.todo "")
--captureNew :
--    Handler
--        (String -> a)
--        (String
--         -> b
--        )
--    ->
--        Handler
--            a
--            b


capture :
    Handler
        (String -> a)
        constructor
    ->
        Handler
            a
            (String -> constructor)
capture (Handler pattern previousHandler toString constructor) =
    Handler
        (pattern ++ "(.*)")
        --(Debug.todo "")
        --(\matches ->
        --    case matches of
        --        first :: rest ->
        --            previousHandler rest
        --
        --        -- first
        --        _ ->
        --            Debug.todo "Expected non-empty list"
        --)
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
                    toString rest ++ first

                _ ->
                    ""
        )
        (\matches ->
            \string ->
                constructor (string :: matches)
        )



--(\_ -> constructor)
--(Debug.todo "")
--)
--foo : a -> List a -> List a
--foo =
--    (::)
--(dynamicSegments (\string -> [ string ]))
--(Debug.todo "")


captureRest : Handler (List String -> a) b -> Handler a b
captureRest previousHandler =
    Debug.todo ""
