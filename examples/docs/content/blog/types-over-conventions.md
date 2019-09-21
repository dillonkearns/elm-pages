---
{
  "type": "blog",
  "author": "Dillon Kearns",
  "title": "Types Over Conventions",
  "description": "How elm-pages approaches configuration, using type-safe Elm.",
  "published": "2019-09-21",
}
---

Rails started a movement of simplifying project setup with [a philosophy of "Convention Over Configuration"](https://rubyonrails.org/doctrine/#convention-over-configuration). This made for a very easy experience bootstrapping a new web server. The downside is that you have a lot of implicit rules that can be hard to follow.

`elm-pages` takes a different approach. Rather than implicit conventions, or verbose configuration, `elm-pages` is centered around letting you explicitly configure your project using Elm's type system. This makes it a lot easier to configure because the Elm compiler will give you feedback on what the valid options are. And it also gives you the ability to define your own defaults and conventions explicitly, giving you the confidence getting started that Rails gives you, but the explicitness and helpful compiler support we're accustomed to in Elm.

**Note:** `elm-pages` currently relies on a few basic conventions such as the name of the `content` folder which has your markup. Convention over configuration isn't evil. It just has a set of tradeoffs, like any other design. `elm-pages` shares the Elm philosophy's idea that ["There are worse things than being explicit"](https://twitter.com/czaplic/status/928359289135046656). In other words, implicit rules that are hard to trace is more likely to cause maintainability issues than a little extra typing to explicitly lay out some core rules. (As long as that extra typing is nice, type-safe Elm code!)

Consider how `elm-pages` handles choosing a template for your pages. Many static site generators use [a special framework-provided frontmatter directive](https://jekyllrb.com/docs/front-matter/#predefined-global-variables) that determines which layout to use. And a special file naming convention will be used as the fallback for the default layout if you don't specify a layout in the frontmatter.

With `elm-pages`, there are no magic frontmatter directives. The way you define and handle your metadata is completely up to you. `elm-pages` simply hands you the metadata types you define and allows you to choose how to handle them with the Elm compiler there to support you.

## Let's see the code!

If we wanted to define a particular layout for blog posts, and a different layout for podcast episodes, then it's as simple as defining a JSON decoder for the data in our frontmatter.

So here's the frontmatter for a blog post:

```markdown
---
author: dillon
title: Types Over Conventions
published: 2019-09-21
---
```

And here's the frontmatter for a regular page:

```markdown
---
title: About elm-pages
---
```

As far as `elm-pages` is concerned, this is just data. We define the rules for what to do with those different data types in our code.

```elm
import Author
import Json.Decode

type Metadata
    = Page { title : String }
    | BlogPost { author : String, title : String }


document =
    Pages.Document.parser
        { extension = "md"
        , metadata =
            Json.Decode.oneOf
            [
            Json.Decode.map
            (\title -> Page { title = title })
            (Json.Decode.field "title" Json.Decode.string)
            , Json.Decode.map2
            (\author title ->
              BlogPost { author = author, title = title }
            )
            (Json.Decode.field "author" Author.decoder)
            (Json.Decode.field "title" Json.Decode.string)
            ]
        , body = markdownView
        }

markdownView : String -> Result String (List (Html Msg))
markdownView markdownBody =
    MarkdownRenderer.view markdownBody
```

Each file in the `content` folder will result in a new route for your static site. You can define how to render the types of document in the `content` folder based on the extension any way you like.

Now, in our `elm-pages` app, our `view` function will get the markdown that we rendered for a given page along with the corresponding `Metadata`. It's completely in our hands what we want to do with that data.

Rails started a movement of simplifying project setup with [a philosophy of "Convention Over Configuration"](https://rubyonrails.org/doctrine/#convention-over-configuration). This made for a very easy experience bootstrapping a new web server. The downside is that you have a lot of implicit rules that can be hard to follow.

`elm-pages` gives you the best of both worlds. Rather than implicit conventions, or verbose configuration, `elm-pages` is centered around letting you explicitly configure your project using Elm's type system. This makes it a lot easier to configure because the Elm compiler will give you feedback on what the valid options are. And it also gives you the ability to define your own defaults and conventions explicitly, giving you the simplicity of the Rails philosophy, but the explicitness and helpful compiler support we're accustomed to in Elm.

**Note:** `elm-pages` currently relies on a few basic conventions such as the name of the `content` folder which has your markup. Convention over configuration isn't evil. It just has a set of tradeoffs, like any other design. `elm-pages` shares the Elm philosophy's idea that ["There are worse things than being explicit"](https://twitter.com/czaplic/status/928359289135046656). In other words, implicit rules that are hard to trace is more likely to cause maintainability issues than a little extra typing to explicitly lay out some core rules. As long as that extra typing is nice, type-safe Elm code!

<Oembed url="https://twitter.com/czaplic/status/928359289135046656" />

Consider how `elm-pages` handles choosing a template for your pages. Many static site generators use [a special framework-provided frontmatter directive](https://jekyllrb.com/docs/front-matter/#predefined-global-variables) that determines which layout to use. And a special file naming convention will be used as the fallback for the default layout if you don't specify a layout in the frontmatter.

With `elm-pages`, there are no magic frontmatter directives. The way you define and handle your metadata is completely up to you. `elm-pages` simply hands you the metadata types you define and allows you to choose how to handle them with the Elm compiler there to support you.

## Let's see the code!

If we wanted to define a particular layout for blog posts, and a different layout for regular pages, then it's as simple as defining a JSON decoder for the data in our frontmatter.

So here's the frontmatter for a blog post:

```markdown
---
author: dillon
title: Types Over Conventions
published: 2019-09-21
---
```

And here's the frontmatter for a regular page:

```markdown
---
title: About elm-pages
---
```

As far as `elm-pages` is concerned, this is just data. We define the rules for what to do with those different data types in our code.

Here's how we set up a parser to handle the frontmatter and body of our `.md` files in our `content` folder.
The raw frontmatter can be a variety of formats, including YAML, TOML, and JSON. But in our Elm code,
we turn that data into the data representing our app's metadata using a `Json.Decoder`.

```elm
import Author
-- Author is our custom module that looks
-- up author data from their first name
import Json.Decode

type Metadata
    = Page { title : String }
    | BlogPost { author : String, title : String }

document =
  Pages.Document.parser
    { extension = "md"
    , metadata =
      Json.Decode.oneOf
        [ Json.Decode.map
          (\title ->
            Page { title = title }
          )
          (Json.Decode.field "title" Json.Decode.string)
        , Json.Decode.map2
          (\author title ->
            BlogPost { author = author, title = title }
          )
          (Json.Decode.field "author" Author.decoder)
          (Json.Decode.field "title" Json.Decode.string)
        ]
    , body = markdownView
    }


markdownView : String -> Result String (List (Html Msg))
markdownView markdownBody =
  MarkdownRenderer.view markdownBody
```

Each file in the `content` folder will result in a new route for your static site. You can define how to render the types of document in the `content` folder based on the extension any way you like.

Now, in our `elm-pages` app, our `view` function will get the markdown that we rendered for a given page along with the corresponding `Metadata`. It's completely in our hands what we want to do with that data.

## Takeaways
So which is better, configuration through types or configuration by convention?

They both have their benefits. If you're like me, then you enjoy being able to figure out what your Elm code is doing by just following the types. And I hope you'll agree that `elm-pages` gives you that experience for wiring up your content and your parsers. 

And when you need to do something more advanced, you've got all the typed data right there and you're empowered to solve the problem using Elm!