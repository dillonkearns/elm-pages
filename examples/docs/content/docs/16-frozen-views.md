---
description: Frozen Views let you render content at build time and eliminate rendering code from your client bundle, giving you smaller bundles and faster page loads.
---

# Frozen Views

Frozen Views are a powerful optimization in elm-pages that lets you:

1. **Render content at build time** - Heavy rendering (markdown parsing, syntax highlighting) happens once during build
2. **Eliminate rendering code from client bundles** - The code used to render frozen content is dead-code eliminated
3. **Adopt pre-rendered HTML seamlessly** - The client "adopts" the pre-rendered DOM without re-rendering

## The Mental Model

Think of `View.freeze` as putting content in ice. Once frozen:

- It's rendered once and preserved exactly as-is
- The client displays it without doing any work
- The freezer (rendering code) can be thrown away after use

```
┌─────────────────────────────────────────────────────────────┐
│                     BUILD TIME                               │
│  Your Elm view code renders frozen content to HTML          │
│  Heavy dependencies (markdown, syntax highlighting) run     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     CLIENT BUNDLE                            │
│  Rendering code for frozen content is ELIMINATED            │
│  Only interactive code remains                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     BROWSER                                  │
│  Pre-rendered HTML is adopted without re-rendering          │
│  Interactive parts hydrate normally                         │
└─────────────────────────────────────────────────────────────┘
```

## When to Use Frozen Views

Use `View.freeze` for content that:

- **Doesn't need interactivity** - No click handlers, no dynamic updates
- **Uses heavy dependencies** - Markdown parsers, syntax highlighters, complex formatting
- **Comes from build-time data** - Content from `app.data` that won't change at runtime

**Don't use** `View.freeze` for content that:

- Needs event handlers (`onClick`, `onInput`, etc.)
- Depends on `model` (client-side state)
- Updates dynamically based on user interaction

## Basic Example

```elm
view : App Data ActionData RouteParams -> Shared.Model -> View (PagesMsg Msg)
view app shared =
    { title = "My Page"
    , body =
        [ -- Frozen: rendered at build time, HTML adopted by client
          View.freeze
            (div []
                [ h1 [] [ text app.data.title ]
                , renderMarkdown app.data.content  -- Heavy markdown parsing
                ]
            )

        -- Interactive: normal Elm view, hydrates on client
        , button [ onClick (PagesMsg.fromMsg Subscribe) ]
            [ text "Subscribe" ]
        ]
    }
```

In this example:
- The title and markdown content are frozen - the markdown parser is eliminated from the client bundle
- The subscribe button is interactive - it works normally with click handlers

## Setting Up Frozen Views

To use frozen views, update your `View.elm` to export the required functions:

```elm
module View exposing (View, map, freeze, Freezable, freezableToHtml, htmlToFreezable)

import Html exposing (Html)


type alias View msg =
    { title : String
    , body : List (Html msg)
    }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.map fn) doc.body
    }


{-| The type of content that can be frozen. Must produce no messages (Never).
-}
type alias Freezable =
    Html Never


{-| Convert Freezable content to plain Html for server-side rendering.
-}
freezableToHtml : Freezable -> Html Never
freezableToHtml =
    identity


{-| Convert plain Html back to Freezable for client-side adoption.
-}
htmlToFreezable : Html Never -> Freezable
htmlToFreezable =
    identity


{-| Freeze content so it's rendered at build time and adopted on the client.

Frozen content:
- Is rendered at build time and included in the HTML
- Is adopted by the client without re-rendering
- Has its rendering code eliminated from the client bundle (DCE)

The content must be `Html Never` (no event handlers allowed).
-}
freeze : Freezable -> Html msg
freeze content =
    content
        |> freezableToHtml
        |> htmlToFreezable
        |> Html.map never
```

## Using with Html.Styled

If you use `elm-css` with `Html.Styled`, update the conversion functions:

```elm
module View exposing (View, map, freeze, Freezable, freezableToHtml, htmlToFreezable)

import Html
import Html.Styled exposing (Html)


type alias View msg =
    { title : String
    , body : List (Html msg)
    }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }


type alias Freezable =
    Html Never


freezableToHtml : Freezable -> Html.Html Never
freezableToHtml =
    Html.Styled.toUnstyled


htmlToFreezable : Html.Html Never -> Freezable
htmlToFreezable =
    Html.Styled.fromUnstyled


freeze : Freezable -> Html msg
freeze content =
    content
        |> freezableToHtml
        |> htmlToFreezable
        |> Html.Styled.map never
```

## Real-World Example: Blog Post

Here's a more complete example showing a blog post with frozen content and interactive features:

```elm
module Route.Blog.Slug_ exposing (Model, Msg, RouteParams, route, Data, ActionData)

import View


type alias Data =
    { title : String
    , author : String
    , content : String        -- Raw markdown
    , publishedAt : Time.Posix
    , commentCount : Int      -- Used in interactive section
    }


type alias Model =
    { showComments : Bool
    }


type Msg
    = ToggleComments


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app shared model =
    { title = app.data.title
    , body =
        [ article []
            [ -- Frozen: metadata and content
              View.freeze
                (header []
                    [ h1 [] [ text app.data.title ]
                    , p [ class "meta" ]
                        [ text ("By " ++ app.data.author)
                        , text " · "
                        , text (formatDate app.data.publishedAt)
                        ]
                    ]
                )

            -- Frozen: heavy markdown rendering
            , View.freeze
                (div [ class "content" ]
                    [ Markdown.toHtml app.data.content ]
                )

            -- Interactive: comment toggle
            , div [ class "comments-section" ]
                [ button [ onClick (PagesMsg.fromMsg ToggleComments) ]
                    [ text
                        (if model.showComments then
                            "Hide Comments"
                         else
                            "Show " ++ String.fromInt app.data.commentCount ++ " Comments"
                        )
                    ]
                , if model.showComments then
                    commentsView app.data.comments
                  else
                    text ""
                ]
            ]
        ]
    }
```

In this example:
- The blog post metadata (title, author, date) is frozen
- The markdown content is frozen - the `Markdown` module is eliminated from the client bundle
- The comments toggle is interactive - it uses `model.showComments` and has a click handler
- `app.data.commentCount` is used in both frozen and interactive contexts, so it's kept in the client data

## How It Works Under the Hood

When you use `View.freeze`, elm-pages:

1. **At build time**: Runs your view code and extracts the HTML from frozen regions
2. **Transforms client code**: Replaces `View.freeze` calls with placeholders that adopt pre-rendered HTML
3. **Dead-code eliminates**: The Elm compiler removes unreferenced rendering code
4. **At runtime**: The client adopts the pre-rendered DOM nodes without re-rendering

### Data Optimization

elm-pages also analyzes which `app.data` fields are used only in frozen contexts:

```elm
type alias Data =
    { title : String           -- Used in frozen AND interactive → kept
    , rawMarkdown : String     -- Used ONLY in frozen → eliminated from client
    , commentCount : Int       -- Used in interactive → kept
    }
```

Fields used only in `View.freeze` or the `head` function are automatically excluded from the client bundle.

## Key Constraints

### Frozen content must be `Html Never`

This is enforced by the type system. `Html Never` means "HTML that can never produce a message" - no event handlers allowed.

```elm
-- This works
View.freeze (div [] [ text "Hello" ])

-- This is a compile error
View.freeze (button [ onClick MyMsg ] [ text "Click" ])
--                    ^^^^^^^^^^^^^^
-- Html Msg is not Html Never
```

### Frozen content cannot use `model`

Frozen content is rendered at build time, before any client-side state exists. You can use `app.data` (build-time data) but not `model` (runtime state).

```elm
-- This works
View.freeze (text app.data.title)

-- This doesn't work (won't compile in a frozen context)
View.freeze (text model.searchQuery)
```

### SPA navigation

When navigating between pages client-side, frozen content is sent as HTML strings and parsed. This means:

- Frozen content works seamlessly with SPA navigation
- Large frozen sections may increase navigation payload size
- The tradeoff is usually worthwhile for the bundle size savings

## Tips for Best Results

1. **Freeze heavy rendering** - Markdown, syntax highlighting, complex formatting
2. **Keep interactivity outside** - Buttons, forms, dynamic content
3. **Group frozen content** - Multiple frozen regions work, but fewer is simpler
4. **Check your bundle size** - Use Elm's `--optimize` flag and check the output size

## See Also

- [Route Modules](/docs/route-modules) - Where view functions are defined
- [File Structure](/docs/file-structure) - Setting up your `View.elm`
