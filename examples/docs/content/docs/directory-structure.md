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
    └── Template/
        ├── Bio.elm     # user-defined template modules
        └── Catalog.elm
    └── Main.elm
```

## `content` folder

Each file in the `content` folder will result in a new route for your static site. You can define how to render the types of document in the `content` folder based on the extension any way you like.

```elm
helloDocument : Pages.Document.DocumentParser Metadata (List (Html Msg))
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
markdownDocument : Pages.Document.DocumentParser Metadata (List (Element Msg))
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

## Modules

### Templates
`src/Template/*.elm`

A template represents a type of page. For example, a BlogPost template could live in `src/Template/BlogPost.elm`. Any files in your `content/` folder with frontmatter that you decode into type `TemplateType.BlogPost` will be rendered using your `BlogPost` template.

Think of each template as having its own mini `elm-pages architecture` lifecycle.

Imagine you have a site called thegreatcomposers.com that lists the greatest works of Classical composers.

Let's say you have a file called `content/catalog/sibelius.md` with these contents:

```markdown
---
template: catalog
composer: Sibelius
---
## Symphony 2, Op. 47
### Notable Recordings
Bernstein Vienna Philharmonic
```

You have a metadata decoder like this:

```elm
module Metadata exposing (Metadata, decoder)

type Metadata = Catalog Composer | Bio Composer

type Composer = Sibelius | Mozart

decoder =
  Decode.string
    |> Decode.field "template"
    |> Decode.andThen (\template ->
       case template of
          "catalog" -> Decode.map Catalog decodeComposer
          "bio" -> Decode.map Bio decodeComposer
    )
```

Now say you navigate to `/catalog/sibelius`. Let's look at the `elm-pages architecture` lifecycle steps that kick in.

### Build

* `staticData` - When you build your site (using `elm-pages build` for prod or `elm-pages develop` in dev mode), the `staticData` will be fetched for this page. Your `staticData` request has access to the page's `Metadata`. So if you wanted to request `api.composers.com/portrait-images/<composer-name>` to get the list of images for each composer's catalog page, you could. Behind the scenes, `elm-pages` will make sure this data is loaded for you in the browser so you have access to this data, even though the API is only hit during the initial build and then stored as a JSON asset for your site.
#### Page Load
* `init` - the page for Sibelius' catalog has its own state. Let's display a Carousel that shows photos of the composer. `init` is called when you navigate to this page. If you navigate to another composer's catalog page, like Mozart, it will call the same `init` function to get a fresh Model for the new page, passing in the metadata for the Mozart page (from the frontmatter in `content/catalog/mozart`.
* `view` given the page's state, metadata, and StaticHttp data, you can render the catalog for Sibelius.
#### Page Interaction
* `update` - if you click the Carousel, the page's state gets updated.


### Shared
`src/Shared.elm`
* `staticData` (loaded per-app, not per-page)
* `View` - the data type that pages render to in your app
* `view` - the top-level view function for your app

### Build
`src/Build.elm`
* `staticData` (build-only)
* `manifest`
* `generateFiles`


### Global Metadata
`src/TemplateType.elm`

This module must define a variant for each template module.