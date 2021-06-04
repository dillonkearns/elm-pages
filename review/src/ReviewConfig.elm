module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.

To add packages that contain rules, add them to this review project using

    `elm install author/packagename`

when inside the directory containing this file.

-}

import NoExposingEverything
import NoImportingEverything
import NoInconsistentAliases
import NoMissingTypeAnnotation
import NoMissingTypeAnnotationInLetIn
import NoMissingTypeExpose
import NoModuleOnExposedNames
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
    [ -- NoExposingEverything.rule
      --, NoImportingEverything.rule []
      --, NoMissingTypeAnnotation.rule
      --, NoMissingTypeAnnotationInLetIn.rule,
      --NoMissingTypeExpose.rule
      --, NoUnused.CustomTypeConstructors.rule []
      --, NoUnused.CustomTypeConstructorArgs.rule
      --, NoUnused.Dependencies.rule
      --, NoUnused.Exports.rule
      NoUnused.Modules.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/StructuredData.elm"
            , "src/Router.elm" -- used in generated code
            ]
    , NoUnused.Parameters.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/HtmlPrinter.elm" -- magic argument in the HtmlPrinter
            ]
    , NoUnused.Patterns.rule
    , NoUnused.Variables.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/DataSource/Glob.elm"
            ]
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
            ]
    , NoUnoptimizedRecursion.rule (NoUnoptimizedRecursion.optOutWithComment "known-unoptimized-recursion")
        |> Rule.ignoreErrorsForDirectories [ "tests" ]
    ]
        |> List.map
            (\rule ->
                rule
                    |> Rule.ignoreErrorsForFiles
                        [ "src/Pages/Internal/Platform/Effect.elm"
                        , "src/Pages/Internal/Platform.elm"
                        , "src/Pages/Internal/Platform/Cli.elm"
                        , "src/SecretsDict.elm"
                        ]
                    |> Rule.ignoreErrorsForDirectories
                        [ "src/ElmHtml"
                        ]
            )
