module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.

To add packages that contain rules, add them to this review project using

    `elm install author/packagename`

when inside the directory containing this file.

-}

import NoInconsistentAliases
import NoModuleOnExposedNames
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
    [ NoUnused.CustomTypeConstructors.rule []
    , NoUnused.CustomTypeConstructorArgs.rule
    , NoUnused.Dependencies.rule
    , NoUnused.Exports.rule
    , NoUnused.Modules.rule
        |> Rule.ignoreErrorsForFiles [ "src/StructuredData.elm" ]
    , NoUnused.Parameters.rule
    , NoUnused.Patterns.rule
    , NoUnused.Variables.rule
    , NoInconsistentAliases.config
        [--( "Html.Attributes", "Attr" )
         --, ( "Json.Decode", "Decode" )
         --, ( "Json.Encode", "Encode" )
        ]
        |> NoInconsistentAliases.noMissingAliases
        |> NoInconsistentAliases.rule
    , NoModuleOnExposedNames.rule
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
            )
