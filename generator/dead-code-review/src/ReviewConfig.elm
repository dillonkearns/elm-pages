module ReviewConfig exposing (config)

import Pages.Review.DeadCodeEliminateData
import Pages.Review.StaticViewTransform
import Review.Rule as Rule exposing (Rule)


config : List Rule
config =
    [ Pages.Review.DeadCodeEliminateData.rule
        |> Rule.filterErrorsForFiles (String.startsWith "app/")
    , Pages.Review.StaticViewTransform.rule
        |> Rule.filterErrorsForFiles (String.startsWith "app/")
    ]
