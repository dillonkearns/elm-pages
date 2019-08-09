module Pages.Manifest.Category exposing
    ( Category
    , books
    , business
    , custom
    , education
    , entertainment
    , finance
    , fitness
    , food
    , games
    , government
    , health
    , kids
    , lifestyle
    , magazines
    , medical
    , music
    , navigation
    , news
    , personalization
    , photo
    , politics
    , productivity
    , security
    , shopping
    , social
    , sports
    , toString
    , travel
    , utilities
    , weather
    )

{-| See <https://github.com/w3c/manifest/wiki/Categories> and
<https://developer.mozilla.org/en-US/docs/Web/Manifest/categories>
-}


toString : Category -> String
toString (Category raw) =
    raw


type Category
    = Category String


custom name =
    Category name


books =
    Category "books"


business =
    Category "business"


education =
    Category "education"


entertainment =
    Category "entertainment"


finance =
    Category "finance"


fitness =
    Category "fitness"


food =
    Category "food"


games =
    Category "games"


government =
    Category "government"


health =
    Category "health"


kids =
    Category "kids"


lifestyle =
    Category "lifestyle"


magazines =
    Category "magazines"


medical =
    Category "medical"


music =
    Category "music"


navigation =
    Category "navigation"


news =
    Category "news"


personalization =
    Category "personalization"


photo =
    Category "photo"


politics =
    Category "politics"


productivity =
    Category "productivity"


security =
    Category "security"


shopping =
    Category "shopping"


social =
    Category "social"


sports =
    Category "sports"


travel =
    Category "travel"


utilities =
    Category "utilities"


weather =
    Category "weather"
