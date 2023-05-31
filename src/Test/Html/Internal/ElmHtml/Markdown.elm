module Test.Html.Internal.ElmHtml.Markdown exposing
    ( MarkdownOptions, MarkdownModel, baseMarkdownModel
    , decodeMarkdownModel
    )

{-| Markdown helpers

@docs MarkdownOptions, MarkdownModel, baseMarkdownModel

@docs decodeMarkdownModel

-}

import Json.Decode exposing (field)
import Test.Internal.KernelConstants exposing (kernelConstants)


{-| Just a default markdown model
-}
baseMarkdownModel : MarkdownModel
baseMarkdownModel =
    { options =
        { githubFlavored = Just { tables = False, breaks = False }
        , defaultHighlighting = Nothing
        , sanitize = False
        , smartypants = False
        }
    , markdown = ""
    }


{-| options markdown expects
-}
type alias MarkdownOptions =
    { githubFlavored : Maybe { tables : Bool, breaks : Bool }
    , defaultHighlighting : Maybe String
    , sanitize : Bool
    , smartypants : Bool
    }


{-| An internal markdown model. Options are the things you give markdown, markdown is the string
-}
type alias MarkdownModel =
    { options : MarkdownOptions
    , markdown : String
    }


{-| decode a markdown model
-}
decodeMarkdownModel : Json.Decode.Decoder MarkdownModel
decodeMarkdownModel =
    field kernelConstants.markdown.markdown Json.Decode.string
        |> Json.Decode.map (MarkdownModel baseMarkdownModel.options)
