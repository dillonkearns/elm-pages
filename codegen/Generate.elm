port module Generate exposing (main)

{-| -}

import Elm exposing (File)
import Elm.Annotation
import Elm.Arg
import Elm.Case
import Elm.CodeGen
import Elm.Declare
import Elm.Op
import Elm.Pretty
import Gen.Basics
import Gen.CodeGen.Generate exposing (Error)
import Gen.Html
import Gen.Html.Attributes
import Gen.List
import Gen.Server.Response
import Gen.String
import Gen.Tuple
import Gen.UrlPath
import GenerateMain
import Pages.Internal.RoutePattern as RoutePattern exposing (RoutePattern)
import Pretty
import Regex exposing (Regex)


type alias Flags =
    { templates : List (List String)
    , basePath : String
    , phase : String
    }


main : Program Flags () ()
main =
    Platform.worker
        { init =
            \{ templates, basePath, phase } ->
                let
                    routes : List RoutePattern.RoutePattern
                    routes =
                        templates
                            |> List.filterMap RoutePattern.fromModuleName
                in
                ( ()
                , onSuccessSend
                    [ file templates basePath
                    , GenerateMain.otherFile routes phase
                    ]
                )
        , update =
            \_ model ->
                ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


file : List (List String) -> String -> Elm.File
file templates basePath =
    let
        routes : List RoutePattern.RoutePattern
        routes =
            templates
                |> List.filterMap RoutePattern.fromModuleName

        segmentsToRouteFn : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        segmentsToRouteFn =
            segmentsToRoute routes

        routeToPathFn : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        routeToPathFn =
            routeToPath routeType routes

        toPath : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        toPath =
            Elm.Declare.fn "toPath"
                (Elm.Arg.varWith "route" routeType.annotation)
                (\route ->
                    Gen.UrlPath.call_.fromString
                        (Gen.String.call_.join
                            (Elm.string "/")
                            (Elm.Op.append
                                baseUrlAsPath.value
                                (routeToPathFn.call route)
                            )
                        )
                        |> Elm.withType (Elm.Annotation.named [ "UrlPath" ] "UrlPath")
                )

        baseUrlAsPath : Elm.Declare.Value
        baseUrlAsPath =
            Elm.Declare.value
                "baseUrlAsPath"
                (Gen.List.call_.filter
                    (Elm.fn (Elm.Arg.var "item")
                        (\item ->
                            Gen.Basics.call_.not
                                (Gen.String.call_.isEmpty item)
                        )
                    )
                    (Gen.String.call_.split (Elm.string "/")
                        baseUrl.value
                    )
                )

        urlToRoute : Elm.Declaration
        urlToRoute =
            Elm.declaration "urlToRoute"
                (Elm.fn
                    (Elm.Arg.varWith "url"
                        (Elm.Annotation.extensible "url" [ ( "path", Elm.Annotation.string ) ])
                    )
                    (\url ->
                        segmentsToRouteFn.call
                            (splitPath.call
                                (url |> Elm.get "path")
                            )
                            |> Elm.withType (Elm.Annotation.maybe routeType.annotation)
                    )
                )

        withoutBaseUrl : Elm.Declaration
        withoutBaseUrl =
            Elm.declaration "withoutBaseUrl"
                (Elm.fn (Elm.Arg.varWith "path" Elm.Annotation.string)
                    (\path ->
                        Elm.ifThen
                            (path |> Gen.String.call_.startsWith baseUrl.value)
                            (Gen.String.call_.dropLeft
                                (Gen.String.call_.length baseUrl.value)
                                path
                            )
                            path
                    )
                )

        toString : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        toString =
            Elm.Declare.fn "toString"
                (Elm.Arg.varWith "route" routeType.annotation)
                (\route -> Gen.UrlPath.toAbsolute (toPath.call route) |> Elm.withType Elm.Annotation.string)

        redirectTo : Elm.Declaration
        redirectTo =
            Elm.declaration "redirectTo"
                (Elm.fn (Elm.Arg.varWith "route" routeType.annotation)
                    (\route ->
                        Gen.Server.Response.call_.temporaryRedirect
                            (toString.call route)
                            |> Elm.withType
                                (Elm.Annotation.namedWith [ "Server", "Response" ]
                                    "Response"
                                    [ Elm.Annotation.var "data"
                                    , Elm.Annotation.var "error"
                                    ]
                                )
                    )
                )

        toLink : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
        toLink =
            Elm.Declare.fn2 "toLink"
                (Elm.Arg.varWith "toAnchorTag"
                    (Elm.Annotation.function
                        [ Elm.Annotation.list (Gen.Html.annotation_.attribute (Elm.Annotation.var "msg"))
                        ]
                        (Elm.Annotation.var "abc")
                    )
                )
                (Elm.Arg.varWith "route" routeType.annotation)
                (\toAnchorTag route ->
                    Elm.apply
                        toAnchorTag
                        [ Elm.list
                            [ route |> toString.call |> Gen.Html.Attributes.call_.href
                            , Gen.Html.Attributes.attribute "elm-pages:prefetch" ""
                            ]
                        ]
                        |> Elm.withType
                            (Elm.Annotation.var "abc")
                )

        link : Elm.Declaration
        link =
            Elm.declaration "link"
                (Elm.fn3
                    (Elm.Arg.var "attributes")
                    (Elm.Arg.var "children")
                    (Elm.Arg.varWith "route" routeType.annotation)
                    (\attributes children route ->
                        toLink.call
                            (Elm.fn
                                (Elm.Arg.var "anchorAttrs")
                                (\anchorAttrs ->
                                    Gen.Html.call_.a
                                        (Elm.Op.append anchorAttrs attributes)
                                        children
                                )
                            )
                            route
                    )
                    |> Elm.withType
                        (Elm.Annotation.function
                            [ Elm.Annotation.list (Gen.Html.annotation_.attribute (Elm.Annotation.var "msg"))
                            , Elm.Annotation.list (Gen.Html.annotation_.html (Elm.Annotation.var "msg"))
                            , routeType.annotation
                            ]
                            (Gen.Html.annotation_.html (Elm.Annotation.var "msg"))
                        )
                )

        baseUrl : Elm.Declare.Value
        baseUrl =
            Elm.Declare.value "baseUrl" (Elm.string basePath)

        routeType : Elm.Declare.Annotation
        routeType =
            Elm.Declare.customType "Route" (routes |> List.map RoutePattern.toVariant)
    in
    Elm.file
        [ "Route" ]
        ([ [ routeType.declaration
           , segmentsToRouteFn.declaration
           , urlToRoute
           , baseUrl.declaration
           , routeToPathFn.declaration
           , baseUrlAsPath.declaration
           , toPath.declaration
           , toString.declaration
           , redirectTo
           , toLink.declaration
           , link
           , withoutBaseUrl
           ]
            |> List.map (Elm.withDocumentation ".")
            |> List.map Elm.exposeConstructor
         , [ splitPath.declaration
           , maybeToList.declaration
           ]
         ]
            |> List.concat
        )


splitPath : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
splitPath =
    Elm.Declare.fn "splitPath"
        (Elm.Arg.varWith "path" Gen.UrlPath.annotation_.urlPath)
        (\path ->
            Gen.List.call_.filter
                (Elm.fn (Elm.Arg.varWith "item" Elm.Annotation.string)
                    (\item -> Elm.Op.notEqual item (Elm.string ""))
                )
                (Gen.String.call_.split (Elm.string "/") path)
        )


maybeToList : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
maybeToList =
    Elm.Declare.fn "maybeToList"
        (Elm.Arg.varWith "maybeString" (Elm.Annotation.maybe Elm.Annotation.string))
        (\maybeString ->
            Elm.Case.maybe maybeString
                { nothing = Elm.list []
                , just = ( "string", \string -> Elm.list [ string ] )
                }
                |> Elm.withType (Elm.Annotation.list Elm.Annotation.string)
        )


segmentsToRoute : List RoutePattern -> Elm.Declare.Function (Elm.Expression -> Elm.Expression)
segmentsToRoute routes =
    Elm.Declare.fn "segmentsToRoute"
        (Elm.Arg.varWith "segments"
            (Elm.Annotation.list Elm.Annotation.string)
        )
        (\_ ->
            let
                alreadyHasCatchallBranch : Bool
                alreadyHasCatchallBranch =
                    routes
                        |> List.map RoutePattern.toVariantName
                        |> List.any
                            (\{ params } ->
                                case params of
                                    [ RoutePattern.OptionalSplatParam2 ] ->
                                        True

                                    _ ->
                                        False
                            )
            in
            (((routes
                |> List.concatMap RoutePattern.routeToBranch
                |> List.map (Tuple.mapSecond (\constructRoute -> Elm.CodeGen.apply [ Elm.CodeGen.val "Just", constructRoute ]))
              )
                ++ (if alreadyHasCatchallBranch then
                        []

                    else
                        [ ( Elm.CodeGen.allPattern, Elm.CodeGen.val "Nothing" ) ]
                   )
             )
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


routeToPath :
    Elm.Declare.Annotation
    -> List RoutePattern
    -> Elm.Declare.Function (Elm.Expression -> Elm.Expression)
routeToPath routeType routes =
    Elm.Declare.fn "routeToPath"
        (Elm.Arg.varWith "route" routeType.annotation)
        (\route_ ->
            Elm.Case.custom route_
                (Elm.Annotation.list Elm.Annotation.string)
                (routes
                    |> List.map
                        (\route ->
                            case
                                RoutePattern.toVariantName route
                                    |> .params
                                    |> List.foldl
                                        (\param soFar ->
                                            soFar
                                                |> Maybe.andThen
                                                    (\staticOnlySoFar ->
                                                        case param of
                                                            RoutePattern.StaticParam staticName ->
                                                                Just (staticOnlySoFar ++ [ toKebab staticName ])

                                                            _ ->
                                                                Nothing
                                                    )
                                        )
                                        (Just [])
                            of
                                Just staticOnlyName ->
                                    Elm.Case.branch
                                        (Elm.Arg.customType
                                            (RoutePattern.toVariantName route |> .variantName)
                                            ()
                                        )
                                        (\_ ->
                                            staticOnlyName
                                                |> List.map (\kebabName -> Elm.string kebabName)
                                                |> Elm.list
                                                |> List.singleton
                                                |> Elm.list
                                        )

                                Nothing ->
                                    Elm.Case.branch
                                        (Elm.Arg.customType
                                            (RoutePattern.toVariantName route |> .variantName)
                                            identity
                                            |> Elm.Arg.item (Elm.Arg.varWith "params" (Elm.Annotation.record []))
                                        )
                                        (\params ->
                                            RoutePattern.toVariantName route
                                                |> .params
                                                |> List.map
                                                    (\param ->
                                                        case param of
                                                            RoutePattern.StaticParam name ->
                                                                [ Elm.string (toKebab name) ]
                                                                    |> Elm.list

                                                            RoutePattern.DynamicParam name ->
                                                                [ Elm.get name params ]
                                                                    |> Elm.list

                                                            RoutePattern.OptionalParam2 name ->
                                                                maybeToList.call (Elm.get name params)

                                                            RoutePattern.RequiredSplatParam2 ->
                                                                Elm.Op.cons (Gen.Tuple.first (Elm.get "splat" params)) (Gen.Tuple.second (Elm.get "splat" params))

                                                            RoutePattern.OptionalSplatParam2 ->
                                                                Elm.get "splat" params
                                                    )
                                                |> Elm.list
                                        )
                        )
                )
                |> Gen.List.call_.concat
                |> Elm.withType (Elm.Annotation.list Elm.Annotation.string)
        )


{-| Decapitalize the first letter of a string.
decapitalize "This is a phrase" == "this is a phrase"
decapitalize "Hello, World" == "hello, World"
-}
decapitalize : String -> String
decapitalize word =
    -- Source: https://github.com/elm-community/string-extra/blob/4.0.1/src/String/Extra.elm
    changeCase Char.toLower word


{-| Change the case of the first letter of a string to either uppercase or
lowercase, depending of the value of `wantedCase`. This is an internal
function for use in `toSentenceCase` and `decapitalize`.
-}
changeCase : (Char -> Char) -> String -> String
changeCase mutator word =
    -- Source: https://github.com/elm-community/string-extra/blob/4.0.1/src/String/Extra.elm
    String.uncons word
        |> Maybe.map (\( head, tail ) -> String.cons (mutator head) tail)
        |> Maybe.withDefault ""


toKebab : String -> String
toKebab string =
    string
        |> decapitalize
        |> String.trim
        |> Regex.replace (regexFromString "([A-Z])") (.match >> String.append "-")
        |> Regex.replace (regexFromString "[_-\\s]+") (always "-")
        |> String.toLower


regexFromString : String -> Regex
regexFromString =
    Regex.fromString >> Maybe.withDefault Regex.never


port onSuccessSend : List File -> Cmd msg


port onFailureSend : List Error -> Cmd msg


port onInfoSend : String -> Cmd msg
