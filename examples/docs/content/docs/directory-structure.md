---
title: Directory Structure
type: doc
---

## Philosophy

As a general rule, `elm-pages` strives to be unopinionated about how you organize
your files (both code and content).

```shell
.
├── content/
├── elm.json
├── images/
├── static/
├── index.js
├── package.json
└── src/
    └── Main.elm
```

## `content` folder

Each file in the `content` folder will result in a new route for your static site. You can define how to render the types of document in the `content` folder based on the extension any way you like.

```elm
helloDocument : Pages.Document.DocumentParser (Metadata msg) (List (Html Msg))
helloDocument =
    Pages.Document.parser
        { extension = "txt"
        , metadata =
            -- pages will use the layout for Docs if they have
            -- `type: doc` in their markdown frontmatter
            Json.Decode.map2
                (\title maybeType ->
                    case maybeType of
                        Just "doc" ->
                            Metadata.Doc { title = title }

                        _ ->
                            Metadata.Page { title = title }
                )
                (Json.Decode.field "title" Json.Decode.string)
                (Json.Decode.field "type" Json.Decode.string
                    |> Json.Decode.maybe
                )
        , body = MarkdownRenderer.view
        }

```

```elm
markdownDocument : Pages.Document.DocumentParser (Metadata msg) (List (Element Msg))
markdownDocument =
    Pages.Document.parser
        { extension = "md"
        , metadata =
            Json.Decode.map2
                (\title maybeType ->
                    case maybeType of
                        Just "doc" ->
                            Metadata.Doc { title = title }

                        _ ->
                            Metadata.Page { title = title }
                )
                (Json.Decode.field "title" Json.Decode.string)
                (Json.Decode.field "type" Json.Decode.string
                    |> Json.Decode.maybe
                )
        , body = MarkdownRenderer.view
        }

```

## Metadata

You define how your metadata is parsed
