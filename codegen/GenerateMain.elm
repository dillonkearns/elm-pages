module GenerateMain exposing (..)

import Elm exposing (File)
import Elm.Annotation as Type
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
import Gen.Path
import Gen.Server.Response
import Gen.String
import Gen.Tuple
import Pages.Internal.RoutePattern as RoutePattern exposing (RoutePattern)
import Pretty
import Regex exposing (Regex)


otherFile : List RoutePattern.RoutePattern -> File
otherFile routes =
    Elm.file [ "Main" ]
        [ Elm.alias "Model"
            (Type.record
                [ ( "global", Type.named [ "Shared" ] "Model" )
                , ( "page", Type.named [] "PageModel" )
                , ( "current"
                  , Type.maybe
                        (Type.record
                            [ ( "path", Type.named [ "Path" ] "Path" )
                            , ( "query", Type.named [ "Path" ] "Path" |> Type.maybe )
                            , ( "fragment", Type.string |> Type.maybe )
                            ]
                        )
                  )
                ]
            )
        , Elm.customType "PageModel"
            ((routes
                |> List.map
                    (\route ->
                        Elm.variantWith
                            ("Model"
                                ++ (RoutePattern.toModuleName route |> String.join "__")
                            )
                            [ Type.named
                                ("Route"
                                    :: RoutePattern.toModuleName route
                                )
                                "Model"
                            ]
                    )
             )
                ++ [ Elm.variantWith "ModelErrorPage____"
                        [ Type.named [ "ErrorPage" ] "Model" ]
                   , Elm.variant "NotFound"
                   ]
            )
        ]
