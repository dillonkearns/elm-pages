module Pages.Manifest.Category exposing
    ( toString, Category
    , books, business, education, entertainment, finance, fitness, food, games, government, health, kids, lifestyle, magazines, medical, music, navigation, news, personalization, photo, politics, productivity, security, shopping, social, sports, travel, utilities, weather
    , custom
    )

{-| See <https://github.com/w3c/manifest/wiki/Categories> and
<https://developer.mozilla.org/en-US/docs/Web/Manifest/categories>

@docs toString, Category

@docs books, business, education, entertainment, finance, fitness, food, games, government, health, kids, lifestyle, magazines, medical, music, navigation, news, personalization, photo, politics, productivity, security, shopping, social, sports, travel, utilities, weather


## Custom categories

@docs custom

-}


{-| Turn a category into its official String representation, as seen
here: <https://github.com/w3c/manifest/wiki/Categories>.
-}
toString : Category -> String
toString (Category raw) =
    raw


{-| Represents a known, valid category, as specified by
<https://github.com/w3c/manifest/wiki/Categories>. If this document is updated
and I don't add it, please open an issue or pull request to let me know!
-}
type Category
    = Category String


{-| It's best to use the pre-defined categories to ensure that clients (Android, iOS,
Chrome, Windows app store, etc.) are aware of it and can handle it appropriately.
But, if you're confident about using a custom one, you can do so with `Pages.Manifest.custom`.
-}
custom : String -> Category
custom name =
    Category name


{-| Creates the described category.
-}
books : Category
books =
    Category "books"


{-| Creates the described category.
-}
business : Category
business =
    Category "business"


{-| Creates the described category.
-}
education : Category
education =
    Category "education"


{-| Creates the described category.
-}
entertainment : Category
entertainment =
    Category "entertainment"


{-| Creates the described category.
-}
finance : Category
finance =
    Category "finance"


{-| Creates the described category.
-}
fitness : Category
fitness =
    Category "fitness"


{-| Creates the described category.
-}
food : Category
food =
    Category "food"


{-| Creates the described category.
-}
games : Category
games =
    Category "games"


{-| Creates the described category.
-}
government : Category
government =
    Category "government"


{-| Creates the described category.
-}
health : Category
health =
    Category "health"


{-| Creates the described category.
-}
kids : Category
kids =
    Category "kids"


{-| Creates the described category.
-}
lifestyle : Category
lifestyle =
    Category "lifestyle"


{-| Creates the described category.
-}
magazines : Category
magazines =
    Category "magazines"


{-| Creates the described category.
-}
medical : Category
medical =
    Category "medical"


{-| Creates the described category.
-}
music : Category
music =
    Category "music"


{-| Creates the described category.
-}
navigation : Category
navigation =
    Category "navigation"


{-| Creates the described category.
-}
news : Category
news =
    Category "news"


{-| Creates the described category.
-}
personalization : Category
personalization =
    Category "personalization"


{-| Creates the described category.
-}
photo : Category
photo =
    Category "photo"


{-| Creates the described category.
-}
politics : Category
politics =
    Category "politics"


{-| Creates the described category.
-}
productivity : Category
productivity =
    Category "productivity"


{-| Creates the described category.
-}
security : Category
security =
    Category "security"


{-| Creates the described category.
-}
shopping : Category
shopping =
    Category "shopping"


{-| Creates the described category.
-}
social : Category
social =
    Category "social"


{-| Creates the described category.
-}
sports : Category
sports =
    Category "sports"


{-| Creates the described category.
-}
travel : Category
travel =
    Category "travel"


{-| Creates the described category.
-}
utilities : Category
utilities =
    Category "utilities"


{-| Creates the described category.
-}
weather : Category
weather =
    Category "weather"
