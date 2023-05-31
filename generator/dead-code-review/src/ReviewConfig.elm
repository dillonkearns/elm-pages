module ReviewConfig exposing (config)

import Pages.Review.DeadCodeEliminateData
import Review.Rule as Rule exposing (Rule)


config : List Rule
config =
    [ Pages.Review.DeadCodeEliminateData.rule ]
