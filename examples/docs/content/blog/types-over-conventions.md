---
{
  "type": "blog",
  "author": "Dillon Kearns",
  "title": "Types Over Conventions",
  "description": "TODO",
  "published": "2019-09-09",
}
---

Rails started a movement of simplifying project setup with [a philosophy of "Convention Over Configuration"](https://rubyonrails.org/doctrine/#convention-over-configuration). This made for a very easy experience bootstrapping a new web server. The downside is that you have a lot of implicit rules that can be hard to follow.

`elm-pages` gives you the best of both worlds. Rather than implicit conventions, or verbose configuration, `elm-pages` is centered around letting you explicitly configure your project using Elm's type system. This makes it a lot easier to configure because the Elm compiler will give you feedback on what the valid options are. And it also gives you the ability to define your own defaults and conventions explicitly, giving you the simplicity of the Rails philosophy, but the explicitness and helpful compiler support we're accustomed to in Elm.

Consider how `elm-pages` handles choosing a template for your pages. Many static site generators use [a special framework-provided frontmatter directive](https://jekyllrb.com/docs/front-matter/#predefined-global-variables) that determines which layout to use. And a special file naming convention will be used as the fallback for the default layout if you don't specify a layout in the frontmatter.

With `elm-pages`, there are no magic frontmatter directives. The way you define and handle your metadata is completely up to you. `elm-pages` simply hands you the metadata types you define and allows you to choose how to handle them with the Elm compiler there to support you.

## Let's see the code!

If we wanted to define a particular layout for blog posts, and a different layout for podcast episodes, then it's as simple as defining a JSON decoder for the data in our frontmatter.

So here's the frontmatter for a blog post:

```markdown
---
author: Dillon Kearns
title: Types Over Conventions
---
```

And here's the frontmatter for a regular page:

```markdown
---
name: About elm-pages
---
```

As far as `elm-pages` is concerned, this is just data. We define the rules for what to do with those different data types in our code.

```elm
type Metadata
    = Page String
    | BlogPost { author : String, title : String }


document : Pages.Document.DocumentParser (Metadata) (List (Html Msg))
document =
    Pages.Document.parser
        { extension = "md"
        , metadata =
            Json.Decode.oneOf
            [
            Json.Decode.field "name" Json.Decode.string
            |> Json.Decode.map Page
            , Json.Decode.map2
            (\author title ->
              BlogPost { author = author, title = title }
            )
            (Json.Decode.field "author" Json.Decode.string)
            (Json.Decode.field "title" Json.Decode.string)
            ]
        , body = markdownView
        }

markdownView : String -> Result String (List (Html Msg))
markdownView markdownBody =
    MarkdownRenderer.view markdownBody
```

Each file in the `content` folder will result in a new route for your static site. You can define how to render the types of document in the `content` folder based on the extension any way you like.
