module ReviewConfig exposing (config)

import Pages.Review.NoContractViolations
import Pages.Review.StaticRegionScope
import Review.Rule as Rule exposing (Rule)


config : List Rule
config =
    [ Pages.Review.NoContractViolations.rule
    , Pages.Review.StaticRegionScope.rule
    ]

