# elm-review-elm-pages

Provides [`elm-review`](https://package.elm-lang.org/packages/jfmengels/elm-review/latest/) rules to REPLACEME.


## Provided rules

- [`No.InvalidCode`](https://package.elm-lang.org/packages/dillonkearns/elm-review-elm-pages/1.0.0/No-InvalidCode) - Reports REPLACEME.


## Configuration

```elm
module ReviewConfig exposing (config)

import No.InvalidCode
import Review.Rule exposing (Rule)

config : List Rule
config =
    [ No.InvalidCode.rule
    ]
```


## Try it out

You can try the example configuration above out by running the following command:

```bash
elm-review --template dillonkearns/elm-review-elm-pages/example
```
