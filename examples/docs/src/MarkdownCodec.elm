module MarkdownCodec exposing (codec)

import Markdown.Block as Block exposing (Block)
import Serialize as S


codec : S.Codec Never Block
codec =
    S.customType
        (\encodeThematicBreak encodeHtmlBlock encodeUnorderedList encodeOrderedList encodeBlockQuote encodeHeading encodeParagraph encodeTable encodeCodeBlock value ->
            case value of
                Block.ThematicBreak ->
                    encodeThematicBreak

                Block.HtmlBlock html ->
                    encodeHtmlBlock html

                Block.UnorderedList listItems ->
                    encodeUnorderedList listItems

                Block.OrderedList int lists ->
                    encodeOrderedList int lists

                Block.BlockQuote blocks ->
                    encodeBlockQuote blocks

                Block.Heading headingLevel inlines ->
                    encodeHeading headingLevel inlines

                Block.Paragraph inlines ->
                    encodeParagraph inlines

                Block.Table header rows ->
                    encodeTable header rows

                Block.CodeBlock record ->
                    encodeCodeBlock record
        )
        |> S.variant0 Block.ThematicBreak
        |> S.variant1 Block.HtmlBlock htmlCodec
        |> S.variant1 Block.UnorderedList (S.list listItemCodec)
        |> S.variant2 Block.OrderedList S.int (S.list (S.list inlineCodec))
        |> S.variant1 Block.BlockQuote (S.list (S.lazy (\() -> codec)))
        |> S.variant2 Block.Heading headingCodec (S.list inlineCodec)
        |> S.variant1 Block.Paragraph (S.list inlineCodec)
        |> S.variant2 Block.Table tableHeaderCodec (S.list (S.list (S.list inlineCodec)))
        |> S.variant1 Block.CodeBlock
            (S.record (\body language -> { body = body, language = language })
                |> S.field .body S.string
                |> S.field .language (S.maybe S.string)
                |> S.finishRecord
            )
        |> S.finishCustomType


tableHeaderCodec :
    S.Codec
        Never
        (List
            { label : List Block.Inline
            , alignment : Maybe Block.Alignment
            }
        )
tableHeaderCodec =
    S.record (\label alignment -> { label = label, alignment = alignment })
        |> S.field .label (S.list inlineCodec)
        |> S.field .alignment (S.maybe alignmentCodec)
        |> S.finishRecord
        |> S.list


alignmentCodec : S.Codec Never Block.Alignment
alignmentCodec =
    S.customType
        (\encodeAlignLeft encodeAlignRight encodeAlignCenter value ->
            case value of
                Block.AlignLeft ->
                    encodeAlignLeft

                Block.AlignRight ->
                    encodeAlignRight

                Block.AlignCenter ->
                    encodeAlignCenter
        )
        |> S.variant0 Block.AlignLeft
        |> S.variant0 Block.AlignRight
        |> S.variant0 Block.AlignCenter
        |> S.finishCustomType


headingCodec : S.Codec Never Block.HeadingLevel
headingCodec =
    S.customType
        (\encodeH1 encodeH2 encodeH3 encodeH4 encodeH5 encodeH6 value ->
            case value of
                Block.H1 ->
                    encodeH1

                Block.H2 ->
                    encodeH2

                Block.H3 ->
                    encodeH3

                Block.H4 ->
                    encodeH4

                Block.H5 ->
                    encodeH5

                Block.H6 ->
                    encodeH6
        )
        |> S.variant0 Block.H1
        |> S.variant0 Block.H2
        |> S.variant0 Block.H3
        |> S.variant0 Block.H4
        |> S.variant0 Block.H5
        |> S.variant0 Block.H6
        |> S.finishCustomType


inlineCodec : S.Codec Never Block.Inline
inlineCodec =
    S.customType
        (\encodeHardLineBreak encodeHtmlInline encodeLink encodeImage encodeEmphasis encodeStrong encodeStrikethrough encodeCodeSpan encodeText value ->
            case value of
                Block.HardLineBreak ->
                    encodeHardLineBreak

                Block.HtmlInline html ->
                    encodeHtmlInline html

                Block.Link string maybeString inlines ->
                    encodeLink string maybeString inlines

                Block.Image string maybeString inlines ->
                    encodeImage string maybeString inlines

                Block.Emphasis inlines ->
                    encodeEmphasis inlines

                Block.Strong inlines ->
                    encodeStrong inlines

                Block.Strikethrough inlines ->
                    encodeStrikethrough inlines

                Block.CodeSpan string ->
                    encodeCodeSpan string

                Block.Text string ->
                    encodeText string
        )
        |> S.variant0 Block.HardLineBreak
        |> S.variant1 Block.HtmlInline htmlCodec
        |> S.variant3 Block.Link S.string (S.maybe S.string) (S.list (S.lazy (\() -> inlineCodec)))
        |> S.variant3 Block.Image S.string (S.maybe S.string) (S.list (S.lazy (\() -> inlineCodec)))
        |> S.variant1 Block.Emphasis (S.list (S.lazy (\() -> inlineCodec)))
        |> S.variant1 Block.Strong (S.list (S.lazy (\() -> inlineCodec)))
        |> S.variant1 Block.Strikethrough (S.list (S.lazy (\() -> inlineCodec)))
        |> S.variant1 Block.CodeSpan S.string
        |> S.variant1 Block.Text S.string
        |> S.finishCustomType


htmlCodec : S.Codec Never (Block.Html Block)
htmlCodec =
    S.customType
        (\encodeHtmlElement encodeHtmlComment encodeProcessingInstruction encodeHtmlDeclaration encodeCdata value ->
            case value of
                Block.HtmlElement tag attributes children ->
                    encodeHtmlElement tag attributes children

                Block.HtmlComment comment ->
                    encodeHtmlComment comment

                Block.ProcessingInstruction string ->
                    encodeProcessingInstruction string

                Block.HtmlDeclaration string1 string2 ->
                    encodeHtmlDeclaration string1 string2

                Block.Cdata string ->
                    encodeCdata string
        )
        |> S.variant3 Block.HtmlElement S.string (S.list htmlAttributeCodec) (S.list (S.lazy (\() -> codec)))
        |> S.variant1 Block.HtmlComment S.string
        |> S.variant1 Block.ProcessingInstruction S.string
        |> S.variant2 Block.HtmlDeclaration S.string S.string
        |> S.variant1 Block.Cdata S.string
        |> S.finishCustomType


htmlAttributeCodec : S.Codec Never { name : String, value : String }
htmlAttributeCodec =
    S.record (\name value -> { name = name, value = value })
        |> S.field .name S.string
        |> S.field .value S.string
        |> S.finishRecord


listItemCodec : S.Codec Never (Block.ListItem Block.Inline)
listItemCodec =
    S.customType
        (\encodeListItem value ->
            case value of
                Block.ListItem task children ->
                    encodeListItem task children
        )
        |> S.variant2 Block.ListItem taskCodec (S.list inlineCodec)
        |> S.finishCustomType


taskCodec : S.Codec Never Block.Task
taskCodec =
    S.customType
        (\encodeNoTask encodeIncompleteTask encodeCompletedTask value ->
            case value of
                Block.NoTask ->
                    encodeNoTask

                Block.IncompleteTask ->
                    encodeIncompleteTask

                Block.CompletedTask ->
                    encodeCompletedTask
        )
        |> S.variant0 Block.NoTask
        |> S.variant0 Block.IncompleteTask
        |> S.variant0 Block.CompletedTask
        |> S.finishCustomType
