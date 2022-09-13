port module Generate exposing (main)

{-| -}

import Elm exposing (File)
import Elm.Annotation
import Elm.Case
import Elm.CodeGen
import Elm.Op
import Elm.Pretty
import Gen.Basics
import Gen.CodeGen.Generate exposing (Error)
import Gen.List
import Gen.Path
import Gen.Server.Response
import Gen.String
import Pages.Internal.RoutePattern as RoutePattern exposing (RoutePattern)
import Pretty


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
        , Elm.declaration "segmentsToRoute"
            (Elm.fn
                ( "segments"
                , Elm.Annotation.list Elm.Annotation.string |> Just
                )
                (\segments ->
                    (routes
                        |> List.concatMap RoutePattern.routeToBranch
                        |> List.map (Tuple.mapSecond (\constructRoute -> Elm.CodeGen.apply [ Elm.CodeGen.val "Just", constructRoute ]))
                        |> Elm.CodeGen.caseExpr (Elm.CodeGen.val "segments")
                    )
                        |> Elm.Pretty.prettyExpression
                        |> Pretty.pretty 120
                        |> Elm.val
                        |> Elm.withType
                            (Elm.Annotation.named [] "Route"
                                |> Elm.Annotation.maybe
                            )
                )
            )
            |> expose
        , Elm.declaration "urlToRoute"
            (Elm.fn
                ( "url"
                , Elm.Annotation.extensible "url" [ ( "path", Elm.Annotation.string ) ]
                    |> Just
                )
                (\url ->
                    url
                        |> Elm.get "path"
                )
            )
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


routeToBranch : RoutePattern -> Elm.Case.Branch
routeToBranch route =
    Elm.Case.branchList 0
        (\_ ->
            Elm.val "Index"
                |> Elm.just
        )


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
