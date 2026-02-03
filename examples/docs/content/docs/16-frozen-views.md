---
description: Frozen Views let you render content at build or server-render time and eliminate rendering code from your client bundle, giving you smaller bundles and faster page loads.
---

# Frozen Views

Frozen Views are an optimization feature in elm-pages. You can think of it like **[`Html.Lazy`](https://package.elm-lang.org/packages/elm/html/latest/Html-Lazy) on steroids**.

> Since all Elm functions are pure we have a guarantee that the same input will always result in the same output. [`Html.Lazy`](https://package.elm-lang.org/packages/elm/html/latest/Html-Lazy) gives us tools to be lazy about building Html that utilize this fact.

-- [`Html.Lazy` docs](https://package.elm-lang.org/packages/elm/html/latest/Html-Lazy)


```elm
Html.Lazy.lazy todaysDateView model.today
-- only re-render when input has changed
```

So Elm's `Html.Lazy` avoids unnecessary re-renders.

`elm-pages`' `View.freeze` takes it a step further - it *never* renders your code on the client-side. In fact, it doesn't even bundle the rendering code or the `Data` fields it depends on! Instead, it does the work to render the HTML for Frozen Views before it ever hits the client-side (at build-time, or at server-render time for server-rendered routes).

## Usage

To use Frozen Views, you wrap part of your view code (must be within a Route Module file) that doesn't depend on dynamic parameters like your `model` with a call to `View.freeze`:

```elm
type alias Data =
    { today : Date
    -- ^ Used ONLY in frozen content, so it's rendered at build time
    --   then eliminated from `content.dat`—never sent to the client!

    , initialCount : Int
    -- ^ Used in `init`, so it IS sent to the client in `content.dat`.
    }


type alias Model =
    { counter : Int }


init : App Data ActionData RouteParams -> ( Model, Effect Msg )
init app =
    ( { counter = app.data.initialCount }
    -- dynamic usage, so this is in the client bundle
    , Effect.none
    )


view :
    App Data ActionData RouteParams
    -> Model
    -> View (PagesMsg Msg)
view app model =
    { title = "My Page"
    , body =
        [ -- FROZEN: This render code will never run on the client!
          View.freeze
            (h1 []
                [ text
                    ("Today's date: "
                        ++ Date.toIsoString app.data.today
                        -- ^ This function and all its dependencies
                        --   are dead-code eliminated from the client!
                    )
                ]
            )

        -- DYNAMIC: Uses `model`
        , div []
            [ button [ onClick (PagesMsg.fromMsg Decrement) ] [ text "-" ]
            , text (String.fromInt model.counter)
            , button [ onClick (PagesMsg.fromMsg Increment) ] [ text "+" ]
            ]
        ]
    }
```

The frozen part renders to HTML at build time (or server-render time for server-rendered routes—and yes, this optimization works for those too!). On the client, that HTML is **adopted** without re-rendering:

```html
<!-- Initial page load: this HTML is already in the page.
     The Elm virtual DOM adopts it—no re-rendering needed!

     For SPA navigations, the frozen HTML is included
     in the content.dat response. -->
<h1>Today's date: 2025-01-27</h1>
```

## Server-Only Regions

`elm-pages` treats certain sections of your Route Modules as **Server-Only**. Using static analysis, `elm-pages` keeps track of which fields in a Route Module's `Data` record are used in **Client Regions**. Any `Data` record fields that are unused in Client Regions *will never be sent to the client*.

That means for example if you have a large markdown `String`, you can have that in your `Data` but you don't need to pay the penalty of sending two different representations of that to the client (the markdown `String` and the HTML).

In addition to that, `elm-pages` erases Server-Only Regions of code when building your client-side JS bundle so that the Elm compiler can perform dead code elimination to drop all of the code and dependencies that become unused.


```elm
type alias Data =
    { title : String
    -- ^ Used in BOTH frozen and client regions → sent to client

    , rawMarkdown : String
    -- ^ Used ONLY in frozen region → never sent to client!

    , comments : List Comment
    -- ^ Used in client region → sent to client
    }

-- SERVER-ONLY REGION: `head` only runs at build/server-render time
-- and this code is not in the client-side JS bundle
head : App Data ActionData RouteParams -> List Head.Tag
head app =
    Seo.summaryLarge
        { title = app.data.title
        , description = app.data.rawMarkdown |> markdownToDescription
        --               ^^^^^^^^^^^^^^^^^^^^
        -- This usage doesn't count as "client usage"—
        -- rawMarkdown is still excluded from `content.dat`!
        }


view :
    App Data ActionData RouteParams
    -> Model
    -> View (PagesMsg Msg)
view app model =
    { title = app.data.title
    , body =
        [ -- SERVER-ONLY REGION: This code only
          -- runs at build/server-render time
          View.freeze
            (div [] [ h1 [] [ text app.data.title ]
            , app.data.rawMarkdown
                |> markdownRenderView
                -- ^ The Markdown code and all its dependencies
                --   are dead-code eliminated from the client bundle!
                ]
            )

        -- CLIENT REGION: This code runs on both server
        -- (to pre-render the initial HTML response) and client
        -- It is therefore included in the client bundle
        , commentsView app.data.comments
        ]
    }
```

🛜 = sent to client | 🗑️ = eliminated

| What the client receives | Without Frozen Views | With Frozen Views |
|--------------------------|:--------------------:|:-----------------:|
| Pre-rendered HTML        | 🛜                   | 🛜                |
| Re-executes render code  | 🛜                   | 🗑️    (Eliminated, similar to what Html.Lazy does)            |
| `app.rawMarkdown` in `content.dat` | 🛜          | 🗑️      (No duplicate data representation, just HTML)          |
| Markdown dependency in JS bundle | 🛜               | 🗑️ (Dead code eliminated!)               |

## Real-World Results

On the elm-pages.com docs site, frozen views cut the bundle size roughly in half:

| Metric  | Before       | With Frozen Views | Savings         |
|---------|--------------|-------------------|-----------------|
| Raw     | 163.3 KB     | 77.7 KB           | -85.5 KB (-52%) |
| Gzipped | 49.8 KB      | 26.4 KB           | -23.3 KB (-47%) |

## When to Use Frozen Views

Use `View.freeze` for content that:

- **Doesn't need interactivity** - No click handlers, no dynamic updates
- **Uses heavy dependencies** - Markdown parsers, syntax highlighters, complex formatting
- **Comes from build-time data** - Content from `app.data` that won't change at runtime

## Is It Inefficient to Send a Lot of HTML?

You may be wondering whether it's inefficient to send all this HTML over pre-rendered for your Frozen Views. Intuitively, it seems efficient to have JavaScript rendering logic that we can re-use. A couple things to consider:

1. JavaScript is more expensive per byte on your browser's CPU cycles ([JavaScript costs 3x more in processing power according to Alex Russell](https://infrequently.org/page/9/#:~:text=Not%20only%20does%20JavaScript%20cost%203x%20more%20in%20processing%20power))
2. Gzip is remarkably good at handling repetitive HTML syntax
3. For a first page load, your `elm-pages` site is sending over pre-rendered HTML anyway. When you use a frozen view, the page just accepts those frozen sections of the view and doesn't need extra rendering, JS code, or `Data` record fields. For subsequent SPA navigations, you will need to send over the HTML for the next page's Frozen Views. However, note that **we have now avoided sending view code for the entire application just to render a single page**!



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
- Is rendered at build time (or server-render time) and included in the HTML
- Is adopted by the client without re-rendering
- Has its rendering code and dependencies eliminated from the client bundle (DCE)

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

## Constraints

### Frozen content must be `Html Never`

This is enforced by the type system. `Html Never` means "HTML that can never produce a message"—no event handlers allowed.

```elm
-- This works
View.freeze (div [] [ text "Hello" ])

-- This is a compile error
View.freeze (button [ onClick MyMsg ] [ text "Click" ])
--                    ^^^^^^^^^^^^^^
-- Html Msg is not Html Never
```

### Frozen content cannot use `model`

Frozen content is rendered at build time (or server-render time), before any client-side state exists. You can use `app.data` (build-time data) but not `model` (runtime state).

```elm
-- This works
View.freeze (text app.data.title)

-- This doesn't work (won't compile in a frozen context)
View.freeze (text model.searchQuery)
```
