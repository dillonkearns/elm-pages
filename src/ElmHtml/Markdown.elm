module ElmHtml.Markdown exposing
    ( MarkdownOptions, MarkdownModel, baseMarkdownModel
    , encodeOptions, encodeMarkdownModel, decodeMarkdownModel
    )

{-| Markdown helpers

@docs MarkdownOptions, MarkdownModel, baseMarkdownModel

@docs encodeOptions, encodeMarkdownModel, decodeMarkdownModel

-}

import Json.Decode exposing (field)
import Json.Encode


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


{-| We don't really care about encoding options right now
TODO: we will if we want to represent things as we do for elm-html
-}
encodeOptions : MarkdownOptions -> Json.Decode.Value
encodeOptions options =
    Json.Encode.null


{-| encode markdown model
-}
encodeMarkdownModel : MarkdownModel -> Json.Decode.Value
encodeMarkdownModel model =
    Json.Encode.object
        [ ( "options", encodeOptions model.options )
        , ( "markdown", Json.Encode.string model.markdown )
        ]


{-| decode a markdown model
-}
decodeMarkdownModel : Json.Decode.Decoder MarkdownModel
decodeMarkdownModel =
    field "markdown" Json.Decode.string
        |> Json.Decode.map (MarkdownModel baseMarkdownModel.options)
