module RawContent exposing (content)

import Pages.Content as Content exposing (Content)
import Dict exposing (Dict)
import Element exposing (Element)


content : { markdown : List ( List String, { frontMatter : String, body : String } ), markup : List ( List String, String ) }
content =
    { markdown = markdown, markup = markup }


markdown : List ( List String, { frontMatter : String, body : String } )
markdown =
    [ ( ["markdown"]
  , { frontMatter = """ {"title":"This is a markdown article"}
"""
    , body = """
# Hey there 👋

Welcome to this markdown document!
""" }
  )

    ]


markup : List ( List String, String )
markup =
    [
    ( ["about"]
      , """|> Article
    title = How I Learned /elm-markup/
    description = How I learned to use elm-markup.

dummy text of the printing and [typesetting industry]{link| url = http://mechanical-elephant.com }. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.
Lorem ipsum dolor sit amet, consectetur adipiscing elit. In id pellentesque elit, id sollicitudin felis. Morbi eu risus molestie enim suscipit auctor. Morbi pharetra, nisl ut finibus ornare, dolor tortor aliquet est, quis feugiat odio sem ut sem. Nullam eu bibendum ligula. Nunc mollis tortor ac rutrum interdum. Nunc ultrices risus eu pretium interdum. Nullam maximus convallis quam vitae ullamcorper. Praesent sapien nulla, hendrerit quis tincidunt a, placerat et felis. Nullam consectetur magna nec lacinia egestas. Aenean rutrum nunc diam.
Morbi ut porta justo. Integer ac eleifend sem. Fusce sed auctor velit, et condimentum quam. Vivamus id mollis libero, mattis commodo mauris. In hac habitasse platea dictumst. Duis eu lobortis arcu, ac volutpat ante. Duis sapien enim, auctor vitae semper vitae, tincidunt et justo. Cras aliquet turpis nec enim mattis finibus. Nulla diam urna, semper ut elementum at, porttitor ut sapien. Pellentesque et dui neque. In eget lectus odio. Fusce nulla velit, eleifend sit amet malesuada ac, hendrerit id neque. Curabitur blandit elit et urna fringilla, id commodo quam fermentum.
But for real, here's a kitten.


|> Image
    src = http://placekitten.com/g/200/300
    description = What a cute kitten.
Lorem ipsum dolor sit amet, consectetur adipiscing elit. In id pellentesque elit, id sollicitudin felis. Morbi eu risus molestie enim suscipit auctor. Morbi pharetra, nisl ut finibus ornare, dolor tortor aliquet est, quis feugiat odio sem ut sem. Nullam eu bibendum ligula. Nunc mollis tortor ac rutrum interdum. Nunc ultrices risus eu pretium interdum. Nullam maximus convallis quam vitae ullamcorper. Praesent sapien nulla, hendrerit quis tincidunt a, placerat et felis. Nullam consectetur magna nec lacinia egestas. Aenean rutrum nunc diam.
Morbi ut porta justo. Integer ac eleifend sem. Fusce sed auctor velit, et condimentum quam. Vivamus id mollis libero, mattis commodo mauris. In hac habitasse platea dictumst. Duis eu lobortis arcu, ac volutpat ante. Duis sapien enim, auctor vitae semper vitae, tincidunt et justo. Cras aliquet turpis nec enim mattis finibus. Nulla diam urna, semper ut elementum at, porttitor ut sapien. Pellentesque et dui neque. In eget lectus odio. Fusce nulla velit, eleifend sit amet malesuada ac, hendrerit id neque. Curabitur blandit elit et urna fringilla, id commodo quam fermentum.

|> Code
    This is a code block
    With Multiple lines

|> H1
    My section on /lists/

What does a *list* look like?

|> List
    1.  This is definitely the first thing.
        Add all together now
        With some Content
    -- Another thing.
        1. sublist
        -- more sublist
            -- indented
        -- other sublist
            -- subthing
            -- other subthing
    -- and yet, another
        --  and another one
            With some content
"""
      )

  ,( ["docs"]
      , """|> Doc
    title = Quick Start

|> Subheading
    This should have an anchor tag.
"""
      )

  ,( []
      , """|> Page
    title = elm-pages - a statically typed site generator


|> Banner
    A *statically typed* site generator

|> Boxes
    |> Box
        body =
            |> H2
                Pure Elm Configuration
            Layouts, styles, even a full-fledged elm application.

            |> H2
                Type-Safe Content
            Configuration, errors for broken links

    |> Box
        body =
            |> H2
                Pure Elm Configuration
            Layouts, styles, even a full-fledged elm application.

            |> H2
                Type-Safe Content
            Configuration, errors for broken links

    |> Box
        body =
            |> H2
                Pure Elm Configuration
            Layouts, styles, even a full-fledged elm application.

            |> H2
                Type-Safe Content
            Configuration, errors for broken links

|> Values
    |> Value
        title = No magic, just types
        body =
            The magic is in how the pieces snap together. The basic platform provided is simple, letting you compose exactly what you need with types to support you.

    |> Value
        title = Extensible through pure elm
        body =
            Behavior is shared through packages exposing simple helper functions to help you build up your data.

    |> Value
        title = If it compiles, it works
        body =
            `elm-pages`{code} just makes more of the things you do in your static site feel like elm. Did you misspell the name of an image asset or a link to a blog post? `elm-pages`{code} will give you a friendly error message and some helpful suggestions.

    |> Value
        title = An extended elm platform
        body =
            `elm-pages`{code} is just elm, but with a broader set of primitives for declaring meta tags to improve SEO, or generate RSS feeds and other files based on your static content.


    |> Value
        title = Blazing fast
        body =
            All you have to do is create your content and choose how to present it. Optimized images, pre-rendered pages, and a snappy lightweight single-page app all come for free.

    |> Value
        title = Simple
        body =
            `elm-pages`{code} gives you the smallest set of core concepts possible, and a type system to make sure all the pieces fit together just right. The rest is up to you. Rather than remember a lot of magic and special cases, you can just rely on your elm types to build what you need with a set of simple primitives.
"""
      )

    ]
