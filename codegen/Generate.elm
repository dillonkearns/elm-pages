port module Generate exposing (main)

{-| -}

import Elm exposing (File)
import Elm.Annotation as Type
import Gen.CodeGen.Generate as Generate exposing (Error)
import Gen.Helper
import Pages.Internal.RoutePattern as RoutePattern


type alias Flags =
    { templates : List (List String)
    }


main : Program Flags () ()
main =
    Platform.worker
        { init =
            \{ templates } ->
                ( ()
                , onSuccessSend [ file templates ]
                )
        , update =
            \_ model ->
                ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


file : List (List String) -> Elm.File
file templates =
    let
        routes : List RoutePattern.RoutePattern
        routes =
            templates
                |> List.filterMap RoutePattern.fromModuleName
    in
    Elm.file [ "Route" ]
        [ Elm.customType "Route"
            (routes
                |> List.map
                    (\route ->
                        route.segments
                            |> List.map
                                (\segment ->
                                    case segment of
                                        RoutePattern.DynamicSegment name ->
                                            name ++ "_"

                                        RoutePattern.StaticSegment name ->
                                            name
                                )
                            |> String.join "__"
                            |> addEnding route.ending
                            |> Elm.variant
                    )
            )
        ]


addEnding : Maybe RoutePattern.Ending -> String -> String
addEnding maybeEnding string =
    case maybeEnding of
        Nothing ->
            string

        Just ending ->
            string
                ++ "__"
                ++ (case ending of
                        RoutePattern.Optional name ->
                            name ++ "__"

                        RoutePattern.RequiredSplat ->
                            "SPLAT_"

                        RoutePattern.OptionalSplat ->
                            "SPLAT__"
                   )


port onSuccessSend : List File -> Cmd msg


port onFailureSend : List Error -> Cmd msg


port onInfoSend : String -> Cmd msg
