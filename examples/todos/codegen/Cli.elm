port module Cli exposing (main)

{-| -}

import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Cli.Validate
import Elm
import Elm.Annotation
import Elm.Case
import Gen.BackendTask
import Gen.Effect
import Gen.Html
import Gen.Platform.Sub
import Gen.Server.Request
import Gen.Server.Response
import Gen.View
import Pages.Generate exposing (Type(..))
import Pages.Internal.RoutePattern as RoutePattern


type alias CliOptions =
    { moduleName : String
    , preRender : Bool
    }


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add
            (OptionsParser.build CliOptions
                |> OptionsParser.with
                    (Option.requiredPositionalArg "module"
                        |> Option.validate (Cli.Validate.regex moduleNameRegex)
                    )
                |> OptionsParser.with
                    (Option.flag "preRender")
            )


moduleNameRegex : String
moduleNameRegex =
    "([A-Z][a-zA-Z0-9_]*)(\\.([A-Z][a-zA-Z_0-9_]*))*"


main : Program.StatelessProgram Never {}
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = program
        }


type alias Flags =
    Program.FlagsIncludingArgv {}


init : Flags -> CliOptions -> Cmd Never
init flags cliOptions =
    let
        file : Elm.File
        file =
            createFile cliOptions.preRender (cliOptions.moduleName |> String.split ".")
    in
    writeFile
        { path = file.path
        , body = file.contents
        }


createFile : Bool -> List String -> Elm.File
createFile preRender moduleName =
    (if preRender then
        let
            hasDynamicRouteSegments : Bool
            hasDynamicRouteSegments =
                RoutePattern.fromModuleName moduleName
                    |> Maybe.map RoutePattern.hasRouteParams
                    |> Maybe.withDefault False
        in
        if hasDynamicRouteSegments then
            Pages.Generate.preRender
                { moduleName = moduleName
                , pages =
                    Gen.BackendTask.succeed
                        (Elm.list [])
                , data =
                    ( Alias (Elm.Annotation.record [])
                    , \routeParams ->
                        Gen.BackendTask.succeed (Elm.record [])
                    )
                , head = \app -> Elm.list []
                }

        else
            Pages.Generate.single
                { moduleName = moduleName
                , data =
                    ( Alias (Elm.Annotation.record [])
                    , Gen.BackendTask.succeed (Elm.record [])
                    )
                , head = \app -> Elm.list []
                }

     else
        Pages.Generate.serverRender
            { moduleName = moduleName
            , action =
                ( Alias (Elm.Annotation.record [])
                , \routeParams ->
                    Gen.Server.Request.succeed
                        (Gen.BackendTask.succeed
                            (Gen.Server.Response.render
                                (Elm.record [])
                            )
                        )
                )
            , data =
                ( Alias (Elm.Annotation.record [])
                , \routeParams ->
                    Gen.Server.Request.succeed
                        (Gen.BackendTask.succeed
                            (Gen.Server.Response.render
                                (Elm.record [])
                            )
                        )
                )
            , head = \app -> Elm.list []
            }
    )
        --|> Pages.Generate.buildNoState
        --    { view =
        --        \_ _ _ ->
        --            Gen.View.make_.view
        --                { title = moduleName |> String.join "." |> Elm.string
        --                , body = Elm.list [ Gen.Html.text "Here is your generated page!!!" ]
        --                }
        --    }
        |> Pages.Generate.buildWithLocalState
            { view =
                \maybeUrl sharedModel model app ->
                    Gen.View.make_.view
                        { title = moduleName |> String.join "." |> Elm.string
                        , body = Elm.list [ Gen.Html.text "Here is your generated page!!!" ]
                        }
            , update =
                \pageUrl sharedModel app msg model ->
                    Elm.Case.custom msg
                        (Elm.Annotation.named [] "Msg")
                        [ Elm.Case.branch0 "NoOp"
                            (Elm.tuple model
                                (Gen.Effect.none
                                    |> Elm.withType effectType
                                )
                            )
                        ]
            , init =
                \pageUrl sharedModel app ->
                    Elm.tuple (Elm.record [])
                        (Gen.Effect.none
                            |> Elm.withType effectType
                        )
            , subscriptions =
                \maybePageUrl routeParams path sharedModel model ->
                    Gen.Platform.Sub.none
            , model =
                Alias (Elm.Annotation.record [])
            , msg =
                Custom [ Elm.variant "NoOp" ]
            }


effectType : Elm.Annotation.Annotation
effectType =
    Elm.Annotation.namedWith [ "Effect" ] "Effect" [ Elm.Annotation.var "msg" ]


port print : String -> Cmd msg


port printAndExitFailure : String -> Cmd msg


port printAndExitSuccess : String -> Cmd msg


port writeFile : { path : String, body : String } -> Cmd msg
