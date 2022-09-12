port module Generate exposing (main)

{-| -}

import Elm exposing (File)
import Gen.CodeGen.Generate exposing (Error)
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
            (routes |> List.map RoutePattern.toVariant)
            |> expose
        , Elm.declaration "baseUrl" (Elm.string "/")
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
