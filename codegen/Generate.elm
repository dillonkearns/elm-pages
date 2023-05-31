port module Generate exposing (main)

{-| -}

import Elm exposing (File)
import Elm.Annotation
import Elm.Case
import Elm.CodeGen
import Elm.Declare
import Elm.Extra exposing (topLevelValue)
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

        segmentsToRouteFn : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        segmentsToRouteFn =
            segmentsToRoute routes

        routeToPathFn : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        routeToPathFn =
            routeToPath routes

        toPath : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        toPath =
            Elm.Declare.fn "toPath"
                ( "route", Elm.Annotation.named [] "Route" |> Just )
                (\route ->
                    Gen.UrlPath.call_.fromString
                        (Gen.String.call_.join
                            (Elm.string "/")
                            (Elm.Op.append
                                baseUrlAsPath.reference
                                (routeToPathFn.call route)
                            )
                        )
                        |> Elm.withType (Elm.Annotation.named [ "UrlPath" ] "UrlPath")
                )

        baseUrlAsPath : { declaration : Elm.Declaration, reference : Elm.Expression, referenceFrom : List String -> Elm.Expression }
        baseUrlAsPath =
            topLevelValue
                "baseUrlAsPath"
                (Gen.List.call_.filter
                    (Elm.fn ( "item", Nothing )
                        (\item ->
                            Gen.Basics.call_.not
                                (Gen.String.call_.isEmpty item)
                        )
                    )
                    (Gen.String.call_.split (Elm.string "/")
                        baseUrl.reference
                    )
                )

        urlToRoute : Elm.Declaration
        urlToRoute =
            Elm.declaration "urlToRoute"
                (Elm.fn
                    ( "url"
                    , Elm.Annotation.extensible "url" [ ( "path", Elm.Annotation.string ) ]
                        |> Just
                    )
                    (\url ->
                        segmentsToRouteFn.call
                            (splitPath.call
                                (url |> Elm.get "path")
                            )
                            |> Elm.withType (Elm.Annotation.maybe (Elm.Annotation.named [] "Route"))
                    )
                )

        withoutBaseUrl : Elm.Declaration
        withoutBaseUrl =
            Elm.declaration "withoutBaseUrl"
                (Elm.fn ( "path", Just Elm.Annotation.string )
                    (\path ->
                        Elm.ifThen
                            (path |> Gen.String.call_.startsWith baseUrl.reference)
                            (Gen.String.call_.dropLeft
                                (Gen.String.call_.length baseUrl.reference)
                                path
                            )
                            path
                    )
                )

        toString : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        toString =
            Elm.Declare.fn "toString"
                ( "route", Elm.Annotation.named [] "Route" |> Just )
                (\route -> Gen.UrlPath.toAbsolute (toPath.call route) |> Elm.withType Elm.Annotation.string)

        redirectTo : Elm.Declaration
        redirectTo =
            Elm.declaration "redirectTo"
                (Elm.fn ( "route", Elm.Annotation.named [] "Route" |> Just )
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

        toLink : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        toLink =
            Elm.Declare.fn2 "toLink"
                ( "toAnchorTag"
                , Elm.Annotation.function
                    [ Elm.Annotation.list (Elm.Annotation.namedWith [ "Html" ] "Attribute" [ Elm.Annotation.var "msg" ])
                    ]
                    (Elm.Annotation.var "a")
                    |> Just
                )
                ( "route", Just (Elm.Annotation.named [] "Route") )
                (\toAnchorTag route ->
                    Elm.apply
                        toAnchorTag
                        [ Elm.list
                            [ route |> toString.call |> Gen.Html.Attributes.call_.href
                            , Gen.Html.Attributes.attribute "elm-pages:prefetch" ""
                            ]
                        ]
                        |> Elm.withType
                            (Elm.Annotation.var "a")
                )

        link : Elm.Declaration
        link =
            Elm.declaration "link"
                (Elm.fn3
                    ( "attributes", Nothing )
                    ( "children", Nothing )
                    ( "route", Just (Elm.Annotation.named [] "Route") )
                    (\attributes children route ->
                        toLink.call
                            (Elm.fn
                                ( "anchorAttrs", Nothing )
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
                            [ Elm.Annotation.list (Elm.Annotation.namedWith [ "Html" ] "Attribute" [ Elm.Annotation.var "msg" ])
                            , Elm.Annotation.list (Elm.Annotation.namedWith [ "Html" ] "Html" [ Elm.Annotation.var "msg" ])
                            , Elm.Annotation.named [] "Route"
                            ]
                            (Elm.Annotation.namedWith [ "Html" ] "Html" [ Elm.Annotation.var "msg" ])
                        )
                )

        baseUrl : { declaration : Elm.Declaration, reference : Elm.Expression, referenceFrom : List String -> Elm.Expression }
        baseUrl =
            topLevelValue "baseUrl" (Elm.string basePath)
    in
    Elm.file
        [ "Route" ]
        ([ [ Elm.customType "Route" (routes |> List.map RoutePattern.toVariant)
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
            |> List.map expose
         , [ splitPath.declaration
           , maybeToList.declaration
           ]
         ]
            |> List.concat
        )


splitPath : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
splitPath =
    Elm.Declare.fn "splitPath"
        ( "path", Just Gen.UrlPath.annotation_.urlPath )
        (\path ->
            Gen.List.call_.filter
                (Elm.fn ( "item", Just Elm.Annotation.string )
                    (\item -> Elm.Op.notEqual item (Elm.string ""))
                )
                (Gen.String.call_.split (Elm.string "/") path)
        )


maybeToList : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
maybeToList =
    Elm.Declare.fn "maybeToList"
        ( "maybeString", Just (Elm.Annotation.maybe Elm.Annotation.string) )
        (\maybeString ->
            Elm.Case.maybe maybeString
                { nothing = Elm.list []
                , just = ( "string", \string -> Elm.list [ string ] )
                }
                |> Elm.withType (Elm.Annotation.list Elm.Annotation.string)
        )


segmentsToRoute :
    List RoutePattern
    -> { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
segmentsToRoute routes =
    Elm.Declare.fn "segmentsToRoute"
        ( "segments"
        , Elm.Annotation.list Elm.Annotation.string |> Just
        )
        (\segments ->
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
    List RoutePattern
    -> { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
routeToPath routes =
    Elm.Declare.fn "routeToPath"
        ( "route", Just (Elm.Annotation.named [] "Route") )
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
                                    Elm.Case.branch0 (RoutePattern.toVariantName route |> .variantName)
                                        (staticOnlyName
                                            |> List.map (\kebabName -> Elm.string kebabName)
                                            |> Elm.list
                                            |> List.singleton
                                            |> Elm.list
                                        )

                                Nothing ->
                                    Elm.Case.branch1 (RoutePattern.toVariantName route |> .variantName)
                                        ( "params", Elm.Annotation.record [] )
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


expose : Elm.Declaration -> Elm.Declaration
expose declaration =
    declaration
        |> Elm.exposeWith
            { exposeConstructor = True
            , group = Nothing
            }


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
