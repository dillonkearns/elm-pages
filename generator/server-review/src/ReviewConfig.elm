module ReviewConfig exposing (config)

import Pages.Review.Canary
import Pages.Review.ServerDataTransform
import Review.Rule as Rule exposing (Rule)


config : List Rule
config =
    [ Pages.Review.ServerDataTransform.rule
        |> Rule.filterErrorsForFiles (String.startsWith "app/")
    , Pages.Review.Canary.rule
    ]
