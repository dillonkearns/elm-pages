---
description: TODO
---

# The elm-pages philosophy

## Composable Building Blocks

Many frameworks provide features like

- Markdown parsing
- Special frontmatter directives
- RSS reader generation

You can do all those things with `elm-pages`, but using the core building blocks

- The `BackendTask` API lets you read from a file, parse frontmatter, and more.
- The data you get from any of those data sources is just typed Elm data. You decide what it means and how to use it.

The goal of `elm-pages` is to get nicely typed data from the right sources (HTTP, files, structured formats like JSON, markdown, etc.), and get that data to the right places in order to build an optimized site with good SEO.

## SEO should be easy

Whether you're building a personal blog, a professional marketing site, or an eCommerce platform, you should have a presentable link preview when you share a page on Twitter or Slack. You put effort into making compelling content. It shouldn't take effort to wire that data in to the right format for OpenGraph tags, Twitter card tags, or JSON-LD structured data.

I've spent too much time opening 1000 tabs to do these things. Elm is incredible at making it easy to structure data correctly with its nice type system and great package documentation.

`elm-pages` makes SEO head tags, like [Open Graph](https://ogp.me/) and [Twitter Cards](https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started), a first-class type-safe API. The `head` function in a Page Module gets access to your `BackendTask` for the page so you can easily use the data you pull in for that page in the pre-rendered head tags.

## Let Elm Shine

Some JAMstack frameworks have a layer of abstraction for building up a local GraphQL data mesh, then querying for it from a page. GraphQL is great for describing typed data and relationships in APIs. But we already have Elm's great type system and a full general purpose programming language!

That's why the `BackendTask` API doesn't add any additional levels of indirection. The goal is to feel like you're just using plain old Elm as much as possible. Of course we want powerful features like being able to pull in markdown files, glob to find files matching a pattern, get HTTP data, and remove unused JSON data. And we want to pull all of that in to the page so it's ready without any loading spinners or `Msg`s. That's where `elm-pages` comes in. But the goal is to create an abstraction that lets you do all those things with a minimal Elm abstraction that lets you just focus on your data modeling and transformations.
