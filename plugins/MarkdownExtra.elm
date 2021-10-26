module MarkdownExtra exposing (extractInlineText)

import Markdown.Block exposing (Block(..), Html(..), Inline(..), ListItem(..))


extractInlineText : List Inline -> String
extractInlineText inlines =
    List.foldl extractTextHelp "" inlines


extractTextHelp : Inline -> String -> String
extractTextHelp inline text =
    case inline of
        Text str ->
            text ++ str

        HardLineBreak ->
            text ++ " "

        CodeSpan str ->
            text ++ str

        Link _ title inlines ->
            text ++ (title |> Maybe.withDefault (extractInlineText inlines))

        Image _ _ inlines ->
            text ++ extractInlineText inlines

        HtmlInline html ->
            case html of
                HtmlElement _ _ blocks ->
                    blocks
                        |> Markdown.Block.foldl
                            (\block soFar ->
                                soFar ++ extractInlineBlockText block
                            )
                            text

                _ ->
                    text

        Strong inlines ->
            text ++ extractInlineText inlines

        Emphasis inlines ->
            text ++ extractInlineText inlines

        Strikethrough inlines ->
            text ++ extractInlineText inlines


extractInlineBlockText : Block -> String
extractInlineBlockText block =
    case block of
        Paragraph inlines ->
            extractInlineText inlines

        HtmlBlock html ->
            case html of
                HtmlElement _ _ blocks ->
                    blocks
                        |> Markdown.Block.foldl
                            (\nestedBlock soFar ->
                                soFar ++ extractInlineBlockText nestedBlock
                            )
                            ""

                _ ->
                    ""

        UnorderedList tight items ->
            items
                |> List.map
                    (\(ListItem task blocks) ->
                        blocks
                            |> List.map extractInlineBlockText
                            |> String.join "\n"
                    )
                |> String.join "\n"

        OrderedList tight int items ->
            items
                |> List.map
                    (\blocks ->
                        blocks
                            |> List.map extractInlineBlockText
                            |> String.join "\n"
                    )
                |> String.join "\n"

        BlockQuote blocks ->
            blocks
                |> List.map extractInlineBlockText
                |> String.join "\n"

        Heading headingLevel inlines ->
            extractInlineText inlines

        Table header rows ->
            [ header
                |> List.map .label
                |> List.map extractInlineText
            , rows
                |> List.map (List.map extractInlineText)
                |> List.concat
            ]
                |> List.concat
                |> String.join "\n"

        CodeBlock { body } ->
            body

        ThematicBreak ->
            ""
