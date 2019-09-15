module Pages.Document exposing
    ( Document
    , DocumentHandler
    , fromList
    , get
    , markupParser
    , parser
    )

{-| The `Document` represents all the ways to handle the frontmatter metadata
and documents found in your `content` folder.

Frontmatter content is turned into JSON, so you can use the familiar Elm JSON decoding
to get frontmatter content. And you'll get helpful error messages if any of
your frontmatter is invalid (which will prevent an invalid production build from
being created!).

It's up to you how you parse your metadata and content. Here's a simple example of
a site that has two types of pages, `blog` posts and `page` (a regular page like `/about` or `/`).

`content/index.md`

```markdown
---
type: page
title: Welcome to my site!
---
# Here's my site!

I built it with `elm-pages`! 🚀
```

`content/blog/hello-world.md`

```markdown
---
type: blog
author: Dillon Kearns
title: Hello, World!
---
# Hello, World! 👋

## This will be parsed as markdown

Hello!!!
```

    -- this example uses elm-explorations/markdown


    import Html exposing (Html)
    import Json.Decode as Decode exposing (Decoder)
    import Markdown
    import Pages.Document

    type Metadata
        = Blog { title : String, description : String, author : String }
        | Page { title : String }

    markdownDocument : ( String, Pages.Document.DocumentHandler Metadata (Html msg) )
    markdownDocument =
        Pages.Document.parser
            { extension = "md"
            , metadata = frontmatterDecoder
            , body = Markdown.toHtml []
            }

    frontmatterDecoder : Decoder Metadata
    frontmatterDecoder =
        Decode.field "type" Decode.string
            |> Decode.andThen
                (\metadataType ->
                    case metadataType of
                        "blog" ->
                            Decode.map3 (\title description author -> { title = title, description = description, author = author })
                                (Decode.field "title" Decode.string)
                                (Decode.field "description" Decode.string)
                                (Decode.field "author" Decode.string)

                        "page" ->
                            Decode.map (\title -> { title = title })
                                (Decode.field "title" Decode.string)
                )

-}

import Dict exposing (Dict)
import Html exposing (Html)
import Json.Decode
import Mark
import Mark.Error


type Document metadata view
    = Document (Dict String (DocumentHandler metadata view))


type DocumentHandler metadata view
    = DocumentHandler
        { frontmatterParser : String -> Result String metadata
        , contentParser : String -> Result String view
        }


get :
    String
    -> Document metadata view
    ->
        Maybe
            { frontmatterParser : String -> Result String metadata
            , contentParser : String -> Result String view
            }
get extension (Document document) =
    document
        |> Dict.get extension
        |> Maybe.map (\(DocumentHandler handler) -> handler)


fromList : List ( String, DocumentHandler metadata view ) -> Document metadata view
fromList list =
    Document (Dict.fromList list)


parser :
    { extension : String
    , metadata : Json.Decode.Decoder metadata
    , body : String -> Result String view
    }
    -> ( String, DocumentHandler metadata view )
parser { extension, body, metadata } =
    ( extension
    , DocumentHandler
        { contentParser = body
        , frontmatterParser =
            \frontmatter ->
                frontmatter
                    |> Json.Decode.decodeString metadata
                    |> Result.mapError Json.Decode.errorToString
        }
    )


markupParser :
    Mark.Document metadata
    -> Mark.Document view
    -> ( String, DocumentHandler metadata view )
markupParser metadataParser markBodyParser =
    ( "emu"
    , DocumentHandler
        { contentParser = renderMarkup markBodyParser
        , frontmatterParser =
            \frontMatter ->
                Mark.compile metadataParser
                    frontMatter
                    |> (\outcome ->
                            case outcome of
                                Mark.Success parsedMetadata ->
                                    Ok parsedMetadata

                                Mark.Failure failure ->
                                    Err "Failure"

                                Mark.Almost failure ->
                                    Err "Almost failure"
                       )
        }
    )


renderMarkup : Mark.Document view -> String -> Result String view
renderMarkup markBodyParser markupBody =
    Mark.compile
        markBodyParser
        (markupBody |> String.trimLeft)
        |> (\outcome ->
                case outcome of
                    Mark.Success renderedView ->
                        Ok renderedView

                    Mark.Failure failures ->
                        failures
                            |> List.map Mark.Error.toString
                            |> String.join "\n"
                            |> Err

                    Mark.Almost failure ->
                        Err "TODO almost failure"
           )
