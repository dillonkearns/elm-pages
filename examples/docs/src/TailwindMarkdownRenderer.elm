module TailwindMarkdownRenderer exposing (renderer)

import Ellie
import Html exposing (Html)
import Html.Attributes as Attr
import Markdown.Block as Block
import Markdown.Html
import Markdown.Renderer
import Oembed
import SyntaxHighlight


renderer : Markdown.Renderer.Renderer (Html msg)
renderer =
    { heading = heading
    , paragraph = Html.p []
    , thematicBreak = Html.hr [] []
    , text = Html.text
    , strong = \content -> Html.strong [ Attr.class "font-bold" ] content
    , emphasis = \content -> Html.em [ Attr.class "italic" ] content
    , blockQuote = Html.blockquote []
    , codeSpan =
        \content ->
            Html.code
                [ Attr.class "font-semibold font-medium !text-code-highlight"
                ]
                [ Html.text content ]
    , link =
        \{ destination } body ->
            Html.a
                [ Attr.href destination
                , Attr.class "underline"
                ]
                body
    , hardLineBreak = Html.br [] []
    , image =
        \image ->
            case image.title of
                Just _ ->
                    Html.img [ Attr.src image.src, Attr.alt image.alt ] []

                Nothing ->
                    Html.img [ Attr.src image.src, Attr.alt image.alt ] []
    , unorderedList =
        \items ->
            Html.ul []
                (items
                    |> List.map
                        (\item ->
                            case item of
                                Block.ListItem task children ->
                                    let
                                        checkbox =
                                            case task of
                                                Block.NoTask ->
                                                    Html.text ""

                                                Block.IncompleteTask ->
                                                    Html.input
                                                        [ Attr.disabled True
                                                        , Attr.checked False
                                                        , Attr.type_ "checkbox"
                                                        ]
                                                        []

                                                Block.CompletedTask ->
                                                    Html.input
                                                        [ Attr.disabled True
                                                        , Attr.checked True
                                                        , Attr.type_ "checkbox"
                                                        ]
                                                        []
                                    in
                                    Html.li [] (checkbox :: children)
                        )
                )
    , orderedList =
        \startingIndex items ->
            Html.ol
                (case startingIndex of
                    1 ->
                        [ Attr.start startingIndex ]

                    _ ->
                        []
                )
                (items
                    |> List.map
                        (\itemBlocks ->
                            Html.li []
                                itemBlocks
                        )
                )
    , html =
        Markdown.Html.oneOf
            [ Markdown.Html.tag "oembed"
                (\url _ ->
                    Oembed.view [] Nothing url
                        |> Maybe.withDefault (Html.div [] [])
                )
                |> Markdown.Html.withAttribute "url"
            , Markdown.Html.tag "ellie-output"
                (\ellieId _ ->
                    Ellie.outputTab ellieId
                )
                |> Markdown.Html.withAttribute "id"
            ]
    , codeBlock = codeBlock
    , table = Html.table []
    , tableHeader = Html.thead []
    , tableBody = Html.tbody []
    , tableRow = Html.tr []
    , strikethrough =
        \children -> Html.del [] children
    , tableHeaderCell =
        \maybeAlignment ->
            let
                attrs =
                    maybeAlignment
                        |> Maybe.map
                            (\alignment ->
                                case alignment of
                                    Block.AlignLeft ->
                                        "left"

                                    Block.AlignCenter ->
                                        "center"

                                    Block.AlignRight ->
                                        "right"
                            )
                        |> Maybe.map Attr.align
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []
            in
            Html.th attrs
    , tableCell =
        \maybeAlignment ->
            let
                attrs =
                    maybeAlignment
                        |> Maybe.map
                            (\alignment ->
                                case alignment of
                                    Block.AlignLeft ->
                                        "left"

                                    Block.AlignCenter ->
                                        "center"

                                    Block.AlignRight ->
                                        "right"
                            )
                        |> Maybe.map Attr.align
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []
            in
            Html.td attrs
    }


rawTextToId : String -> String
rawTextToId rawText =
    rawText
        |> String.split " "
        |> String.join "-"
        |> String.toLower


heading : { level : Block.HeadingLevel, rawText : String, children : List (Html msg) } -> Html msg
heading { level, rawText, children } =
    case level of
        Block.H1 ->
            Html.h1
                [ Attr.class "text-4xl font-bold tracking-tight mt-2 mb-4"
                ]
                children

        Block.H2 ->
            Html.h2
                [ Attr.id (rawTextToId rawText)
                , Attr.attribute "name" (rawTextToId rawText)
                , Attr.class "text-3xl font-semibold tracking-tight mt-10 pb-1 border-b"
                ]
                [ Html.a
                    [ Attr.href <| "#" ++ rawTextToId rawText
                    , Attr.class "!no-underline"
                    ]
                    (children
                        ++ [ Html.span
                                [ Attr.class "anchor-icon ml-2 text-gray-500 select-none"
                                ]
                                [ Html.text "#" ]
                           ]
                    )
                ]

        _ ->
            (case level of
                Block.H1 ->
                    Html.h1

                Block.H2 ->
                    Html.h2

                Block.H3 ->
                    Html.h3

                Block.H4 ->
                    Html.h4

                Block.H5 ->
                    Html.h5

                Block.H6 ->
                    Html.h6
            )
                [ Attr.class "font-bold text-lg mt-8 mb-4"
                ]
                children


codeBlock : { body : String, language : Maybe String } -> Html msg
codeBlock details =
    SyntaxHighlight.elm details.body
        |> Result.map (SyntaxHighlight.toBlockHtml (Just 1))
        |> Result.withDefault (Html.pre [] [ Html.code [] [ Html.text details.body ] ])
