module Pages.Review.Canary exposing (rule)

{-| A rule that always reports exactly one error.

`elm-pages build` relies on elm-review to transform frozen views and to remove
dead code. If elm-review gives back an empty report (as old elm-review versions
do when their rules are built with Lamdera), the build would carry on without
those transforms and nobody would notice.

So every review config that elm-pages runs includes this rule, and the build
checks that its one error is in the report (see `generator/src/review-report.js`).
No canary means the rules did not really run, and the build stops.

-}

import Review.Rule as Rule exposing (Rule)


rule : Rule
rule =
    Rule.newProjectRuleSchema "Pages.Review.Canary" ()
        |> Rule.withElmJsonProjectVisitor (\_ context -> ( [], context ))
        |> Rule.withFinalProjectEvaluation
            (\_ ->
                [ Rule.globalError
                    { message = "ELM_PAGES_REVIEW_CANARY"
                    , details = [ "This is not a problem in your code. elm-pages uses this message to check that elm-review really ran." ]
                    }
                ]
            )
        |> Rule.fromProjectRuleSchema
