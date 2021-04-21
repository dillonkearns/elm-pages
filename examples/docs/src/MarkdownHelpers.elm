module MarkdownHelpers exposing (..)

import Markdown.Block as Block exposing (Block, Inline)


withToc : List Block -> ( TableOfContents, List Block )
withToc blocks =
    ( buildToc blocks, blocks )


buildToc : List Block -> TableOfContents
buildToc blocks =
    let
        headings =
            gatherHeadings blocks
    in
    headings
        --|> List.map Tuple.second
        |> List.map
            (\( headingLevel, styledList ) ->
                { anchorId = styledToString styledList |> rawTextToId
                , name = styledToString styledList
                , level = Block.headingLevelToInt headingLevel
                }
            )



--headingToLevel =
--    Markdown.Block.headingLevelToInt


type alias TableOfContents =
    List { anchorId : String, name : String, level : Int }


gatherHeadings : List Block -> List ( Block.HeadingLevel, List Inline )
gatherHeadings blocks =
    List.filterMap
        (\block ->
            case block of
                Block.Heading level content ->
                    Just ( level, content )

                _ ->
                    Nothing
        )
        blocks


rawTextToId : String -> String
rawTextToId rawText =
    rawText
        |> String.split " "
        |> String.join "-"
        |> String.toLower


styledToString : List Inline -> String
styledToString inlines =
    --List.map .string list
    --|> String.join "-"
    -- TODO do I need to hyphenate?
    inlines
        |> Block.extractInlineText
