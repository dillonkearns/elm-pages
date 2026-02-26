module ReviewConfig exposing (config)

import Pages.Review.ServerDataTransform
import Review.Rule exposing (Rule)


config : List Rule
config =
    [ Pages.Review.ServerDataTransform.rule
    ]
