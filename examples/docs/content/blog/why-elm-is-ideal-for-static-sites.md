---
{
  "author": "Dillon Kearns",
  "title": "Why Elm is awesome for building a static site framework",
  "description": "",
  "image": "v1603304397/elm-pages/article-covers/extensible-markdown-parsing_x9oolz.jpg",
  "published": "2021-06-25",
}
---

## Isomorphic by design

With JavaScript-based frameworks, the Node and Browser ecosystems are intertwined. In fact, it's not uncommon to include shims for Node's filesystem package to make NPM packages run on the browser.

The main places these language features happen are:

- Global variables (like `window` vs. `globals`)
- Import syntax (`require` vs. `import`)
- Runtime-specific bindings (like `fetch`, `fs.writeFile`, `localStorage`)

For an Elm-based framework, there is a lot less to think about here because:

- Elm doesn't have global variables (everything must be passed in explicitly)
- Elm doesn't have different import syntax options
- Elm has managed effects, i.e. side-effects as data - you can't run side-effects anywhere, so `elm-pages` is able to explicitly choose what side-effects can happen and from where

## Determinism

You can be sure that you don't depend on environment, you can pass in exactly what the use should have access to and that's all their code can depend on. No need to have discipline, the types give guardrails and then you can do anything you want within them.

## Elm is amazing for transforming data

## Validate data for more guarantees

Not only is Elm amazing at working with and transforming data, but it excels at giving guarantees. Once you've checked the data's integrity, you can represent that with the type (think a ValidatedEmail type, or a NonEmptyList). Ideally, you will [[make-impossible-states-impossible]] in the process.

Once your `elm-pages build` command succeeds, you know that all of your validations checked out!

Often Elm code will use the pattern to [[conditionally return a validated type]]. This is great because you can provide strong guarantees that your Elm type is valid and then work with it beyond that point. But it's not good because you split your code into lots of code paths, and you have no way to guarantee that the user won't go down the bad code paths - you just know that if they do, those bad cases are handled explicitly, and you won't get any implicit failures where things silently fail in surprising ways.

Elm is great at giving you errors up front because it checks the contract before passing data along. For example, with a JSON decoder, the decoding fails if there is an unexpected null anywhere. This means you can trust your data integrity before you ever pass it down the line. You don't have to wonder whether you ran through the right code paths to find out whether there was a problem with your data or not. This pairs even better with `elm-pages` because you can find out about these problems at build-time rather than at runtime!

Elm combined with a build phase, like `elm-pages` provides, is an incredible combination because now you can guarantee the happy code path! For pre-rendered pages, you know that the data was solid if the build succeeded. The error code paths are easily handled because you can use `DataSource.fail` to give a custom build error message at any point. Or if anything goes wrong reading a file, decoding frontmatter, performing an HTTP DataSource, then you handle that error as a build error, not an error code path that the user may encounter.

`elm-pages` can also give you great error feedback for free. In the dev server, any time you change your Elm code you get quick feedback showing you any DataSource failures for the current page. In a regular application, you would need to do some wiring to present these errors in a usable way, but with the `elm-pages` architecture it comes for free as part of the core experience.

## Easier wiring

Elm's sound type system, immutability, and explicitness (no magic) make it very easy to trace code. With `elm-pages`, you get those same benefits for reasoning about your code, but the abstraction of a `DataSource` gives you a declarative way to wire in that type-safe data with a lot less wiring.
