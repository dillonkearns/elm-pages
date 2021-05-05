module ApiHandler exposing (..)

import DataSource exposing (DataSource)
import Regex exposing (Regex)


firstMatch : String -> List (Done response) -> Maybe (Done response)
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


tryMatchDone : String -> Done response -> Maybe (Done response)
tryMatchDone path handler =
    if Regex.contains handler.regex path then
        Just handler

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
    , buildTimeRoutes : DataSource (List String)
    , handleRoute : String -> DataSource Bool
    }


singleRoute : Handler response (List String) -> Done response
singleRoute handler =
    handler
        |> done (\constructor -> DataSource.succeed [ constructor ])


done : (constructor -> DataSource (List (List String))) -> Handler response constructor -> Done response
done buildUrls (Handler pattern handler toString constructor) =
    let
        buildTimeRoutes =
            buildUrls (constructor [])
                |> DataSource.map (List.map toString)

        preBuiltMatches : DataSource (List (List String))
        preBuiltMatches =
            buildUrls (constructor [])
    in
    { regex = Regex.fromString pattern |> Maybe.withDefault Regex.never
    , matchesToResponse = \path -> tryMatch path (Handler pattern handler toString constructor)
    , buildTimeRoutes = buildTimeRoutes
    , handleRoute =
        \path -> DataSource.succeed True
    }


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


type Handler a constructor
    = Handler String (List String -> a) (List String -> String) (List String -> constructor)


type alias Response =
    { body : String }


succeed : a -> Handler a (List String)
succeed a =
    Handler "" (\args -> a) (\_ -> "") (\list -> list)


literal : String -> Handler a constructor -> Handler a constructor
literal segment (Handler pattern handler toString constructor) =
    Handler (pattern ++ segment) handler (\values -> toString values ++ segment) constructor


slash : Handler a constructor -> Handler a constructor
slash (Handler pattern handler toString constructor) =
    Handler (pattern ++ "/") handler (\arg -> toString arg ++ "/") constructor


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


captureRest : Handler (List String -> a) b -> Handler a b
captureRest previousHandler =
    Debug.todo ""
