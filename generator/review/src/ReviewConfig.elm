module ReviewConfig exposing (config)

import Pages.Review.NoContractViolations
import Pages.Review.NoInvalidFreeze
import Review.Rule as Rule exposing (Rule)


config : List Rule
config =
    [ Pages.Review.NoContractViolations.rule
    , Pages.Review.NoInvalidFreeze.rule
    ]

