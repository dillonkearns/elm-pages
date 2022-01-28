module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.

To add packages that contain rules, add them to this review project using

    `elm install author/packagename`

when inside the directory containing this file.

-}

import NoDebug.Log
import NoDebug.TodoOrToString
import NoExposingEverything
import NoImportingEverything
import NoInconsistentAliases
import NoMissingTypeAnnotation
import NoMissingTypeAnnotationInLetIn
import NoMissingTypeExpose
import NoModuleOnExposedNames
import NoUnmatchedUnit
import NoUnoptimizedRecursion
import NoUnused.CustomTypeConstructorArgs
import NoUnused.CustomTypeConstructors
import NoUnused.Dependencies
import NoUnused.Exports
import NoUnused.Modules
import NoUnused.Parameters
import NoUnused.Patterns
import NoUnused.Variables
import Review.Rule as Rule exposing (Rule)


config : List Rule
config =
    ([ NoExposingEverything.rule

     --NoImportingEverything.rule []
     , NoInconsistentAliases.config
        [ ( "Html.Attributes", "Attr" )

        --, ( "Json.Encode", "Encode" )
        ]
        |> NoInconsistentAliases.noMissingAliases
        |> NoInconsistentAliases.rule
     , NoModuleOnExposedNames.rule
        |> Rule.ignoreErrorsForFiles
            [ -- Glob module ignored because of https://github.com/sparksp/elm-review-imports/issues/3#issuecomment-854262659
              "src/DataSource/Glob.elm"
            , "src/ApiRoute.elm"
            ]
     , NoUnoptimizedRecursion.rule (NoUnoptimizedRecursion.optOutWithComment "known-unoptimized-recursion")
        |> ignoreInTest
     , NoDebug.Log.rule
        |> ignoreInTest
     , NoDebug.TodoOrToString.rule
        |> ignoreInTest
     , NoMissingTypeAnnotation.rule
     , NoMissingTypeAnnotationInLetIn.rule
        |> Rule.ignoreErrorsForFiles
            [ "tests/FormTests.elm"
            ]
     , NoMissingTypeExpose.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/Head/Seo.elm"
            , "src/DataSource/Glob.elm" -- incorrect result,
            , "src/Pages/Internal/Platform/Effect.elm"
            , "src/Pages/Internal/Platform/Cli.elm"
            , "src/Pages/Internal/Platform.elm"

            -- alias is exposed - see https://github.com/jfmengels/elm-review-common/issues/1
            , "src/ApiRoute.elm" -- incorrect result
            ]
     , NoUnmatchedUnit.rule
     ]
        ++ (noUnusedRules
                |> List.map
                    (\rule ->
                        rule
                            |> Rule.ignoreErrorsForFiles
                                [ "src/Pages/Internal/Platform/Effect.elm"
                                , "src/Pages/Internal/Platform.elm"
                                , "src/Pages/Internal/Platform/Cli.elm"
                                , "src/SecretsDict.elm"
                                , "src/StructuredData.elm"
                                , "src/Router.elm" -- used in generated code
                                , "src/RoutePattern.elm" -- used in generated code
                                , "src/Pages/Http.elm" -- reports incorrect unused custom type constructor
                                , "src/DataSource/ServerRequest.elm" -- temporarily removed from exposed modules for alpha serverless
                                , "src/BuildError.elm"
                                , "src/Internal/ApiRoute.elm"
                                , "src/Pages/StaticHttpRequest.elm"
                                , "src/RenderRequest.elm"
                                , "tests/Pages/Internal/Platform.elm"
                                , "tests/Pages/Internal/Router.elm"
                                ]
                    )
           )
    )
        |> List.map
            (\rule ->
                rule
                    |> Rule.ignoreErrorsForDirectories
                        [ "src/ElmHtml"
                        , "src/Test"
                        ]
            )


noUnusedRules : List Rule
noUnusedRules =
    [ NoUnused.CustomTypeConstructors.rule []
        |> ignoreInTest
        |> Rule.ignoreErrorsForFiles
            [ "src/Head/Twitter.elm" -- keeping unused for future use for spec API
            , "src/RoutePattern.elm"
            , "src/Form.elm" -- ignored because false positive for unused for Phantom Builder type, see https://github.com/jfmengels/elm-review-unused/issues/60
            ]
    , NoUnused.CustomTypeConstructorArgs.rule
        |> ignoreInTest
        |> Rule.ignoreErrorsForFiles
            [ "src/Pages/Http.elm" -- Error type mirrors elm/http Error type
            ]
    , NoUnused.Dependencies.rule
    , NoUnused.Exports.rule
        |> ignoreInTest
        |> Rule.ignoreErrorsForFiles
            [ "src/TerminalText.elm" -- allow some unused exports for colors that could be used later
            ]
    , NoUnused.Modules.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/StructuredData.elm"
            , "src/Router.elm" -- used in generated code
            ]
    , NoUnused.Parameters.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/HtmlPrinter.elm" -- magic argument in the HtmlPrinter
            , "src/FormDecoder.elm" -- magic argument that is tweaked in the JS output
            ]
    , NoUnused.Patterns.rule
    , NoUnused.Variables.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/DataSource/Glob.elm"
            ]
    ]


ignoreInTest : Rule -> Rule
ignoreInTest rule =
    rule
        |> Rule.ignoreErrorsForDirectories [ "tests" ]
