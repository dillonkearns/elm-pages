port module Generate exposing (main)

{-| -}

import Elm exposing (File)
import Elm.Annotation
import Elm.Op
import Gen.Basics
import Gen.CodeGen.Generate exposing (Error)
import Gen.List
import Gen.Path
import Gen.Server.Response
import Gen.String
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
    Elm.file
        [ "Route" ]
        [ Elm.customType "Route"
            (routes |> List.map RoutePattern.toVariant)
            |> expose
        , Elm.declaration "baseUrl" (Elm.string "/")
            |> expose
        , Elm.declaration "baseUrlAsPath"
            (Gen.List.call_.filter
                (Elm.fn ( "item", Nothing )
                    (\item ->
                        Gen.Basics.call_.not
                            (Gen.String.call_.isEmpty item)
                    )
                )
                (Gen.String.call_.split (Elm.string "/")
                    (Elm.val "baseUrl")
                )
            )
            |> expose
        , Elm.declaration "toPath"
            (Elm.fn ( "route", Elm.Annotation.named [] "Route" |> Just )
                (\route ->
                    Gen.Path.call_.fromString
                        (Gen.String.call_.join
                            (Elm.string "/")
                            (Elm.Op.append
                                (Elm.val "baseUrlAsPath")
                                (Elm.apply (Elm.val "routeToPath")
                                    [ route ]
                                )
                            )
                        )
                )
            )
            |> expose
        , Elm.declaration "toString"
            (Elm.fn ( "route", Elm.Annotation.named [] "Route" |> Just )
                (\route ->
                    Gen.Path.toAbsolute
                        (Elm.apply (Elm.val "toPath") [ route ])
                )
            )
            |> expose
        , Elm.declaration "redirectTo"
            (Elm.fn ( "route", Elm.Annotation.named [] "Route" |> Just )
                (\route ->
                    Gen.Server.Response.call_.temporaryRedirect
                        route
                )
            )
            |> expose
        ]


expose : Elm.Declaration -> Elm.Declaration
expose declaration =
    declaration
        |> Elm.exposeWith
            { exposeConstructor = True
            , group = Nothing
            }


port onSuccessSend : List File -> Cmd msg


port onFailureSend : List Error -> Cmd msg


port onInfoSend : String -> Cmd msg
