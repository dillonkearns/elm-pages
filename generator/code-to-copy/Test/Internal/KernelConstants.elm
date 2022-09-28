module Test.Internal.KernelConstants exposing (kernelConstants)

{-| This module defines the mapping of optimized field name and enum values
for kernel code in other packages the we depend on.
-}


{-| NOTE: this is duplicating constants also defined in src/Elm/Kernel/HtmlAsJson.js
so if you make any changes here, be sure to synchronize them there!
-}
kernelConstants =
    { virtualDom =
        { nodeType = "$"
        , nodeTypeText = 0
        , nodeTypeKeyedNode = 2
        , nodeTypeNode = 1
        , nodeTypeCustom = 3
        , nodeTypeTagger = 4
        , nodeTypeThunk = 5
        , tag = "c"
        , kids = "e"
        , facts = "d"
        , descendantsCount = "b"
        , text = "a"
        , refs = "l"
        , node = "k"
        , tagger = "j"
        , model = "g"
        }
    , markdown =
        { options = "a"
        , markdown = "b"
        }
    }
