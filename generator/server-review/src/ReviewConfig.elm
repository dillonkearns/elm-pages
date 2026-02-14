module ReviewConfig exposing (config)

import Pages.Review.ServerDataTransform
import Review.Rule as Rule exposing (Rule)


config : List Rule
config =
    [ Pages.Review.ServerDataTransform.rule
        |> Rule.filterErrorsForFiles (String.startsWith "app/")
    ]
