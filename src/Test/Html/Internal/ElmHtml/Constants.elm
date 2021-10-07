module Test.Html.Internal.ElmHtml.Constants exposing
    ( propKey, styleKey, eventKey, attributeKey, attributeNamespaceKey
    , knownKeys
    )

{-| Constants for representing internal keys for Elm's vdom implementation

@docs propKey, styleKey, eventKey, attributeKey, attributeNamespaceKey
@docs knownKeys

-}


{-| Internal key for attribute properties
-}
propKey : String
propKey =
    "a2"


{-| Internal key for style
-}
styleKey : String
styleKey =
    "a1"


{-| Internal key for style
-}
eventKey : String
eventKey =
    "a0"


{-| Internal key for style
-}
attributeKey : String
attributeKey =
    "a3"


{-| Internal key for style
-}
attributeNamespaceKey : String
attributeNamespaceKey =
    "a4"


{-| Keys that we are aware of and should pay attention to
-}
knownKeys : List String
knownKeys =
    [ styleKey, eventKey, attributeKey, attributeNamespaceKey ]
