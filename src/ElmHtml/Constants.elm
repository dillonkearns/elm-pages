module ElmHtml.Constants exposing (styleKey, eventKey, attributeKey, attributeNamespaceKey, knownKeys)

{-| Constants for representing internal keys for Elm's vdom implementation

@docs styleKey, eventKey, attributeKey, attributeNamespaceKey, knownKeys

-}


{-| Internal key for style
-}
styleKey : String
styleKey =
    "a1"


{-| Internal key for 'on' events
-}
eventKey : String
eventKey =
    "a0"

propertyKey : String
propertyKey =
    "a2"

{-| Internal key for attributes
-}
attributeKey : String
attributeKey =
    "a3"


{-| Internal key for namespaced attributes
-}
attributeNamespaceKey : String
attributeNamespaceKey =
    "a4"


{-| Keys that we are aware of and should pay attention to
-}
knownKeys : List String
knownKeys =
    [ styleKey, eventKey, attributeKey, attributeNamespaceKey ]
