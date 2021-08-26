module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.

To add packages that contain rules, add them to this review project using

    `elm install author/packagename`

when inside the directory containing this file.

-}

import NoForbiddenWords
import NoUnused.CustomTypeConstructorArgs
import NoUnused.CustomTypeConstructors
import NoUnused.Dependencies
import NoUnused.Exports
import NoUnused.Modules
import NoUnused.Parameters
import NoUnused.Patterns
import NoUnused.Variables
import Pages.Review.NoContractViolations
import Review.Rule exposing (Rule)


config : List Rule
config =
    [ NoUnused.CustomTypeConstructors.rule []
    , NoUnused.CustomTypeConstructorArgs.rule
    , NoUnused.Dependencies.rule

    --, NoUnused.Exports.rule
    , NoUnused.Modules.rule

    --, NoUnused.Parameters.rule
    --, NoUnused.Patterns.rule
    --, NoUnused.Variables.rule
    , NoForbiddenWords.rule [ "TODO" ]
    , Pages.Review.NoContractViolations.rule
    ]
        |> List.map
            (\rule ->
                rule
                    |> Review.Rule.ignoreErrorsForDirectories [ "../../src", ".elm-pages/" ]
            )
