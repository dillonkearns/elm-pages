# The elm-pages philosophy

## Composable Building Blocks

Many frameworks provide features like

- Markdown parsing
- Special frontmatter directives
- RSS reader generation

You can do all those things with `elm-pages`, but using the core building blocks

- The `DataSource` API lets you read from a file, parse frontmatter, and more.
- The data you get from any of those data sources is just typed Elm data. You decide what it means and how to use it.

The goal of `elm-pages` is to get nicely typed data from the right sources (HTTP, files, structured formats like JSON, markdown, etc.), and get that data to the right places in order to build an optimized site with good SEO.

## SEO should be easy

Whether you're building a personal blog, a professional marketing site, or an eCommerce platform, you should have a presentable link preview when you share a page on Twitter or Slack. You put effort into making compelling content. It shouldn't take effort to wire that data in to the right format for OpenGraph tags, Twitter card tags, or JSON-LD structured data.

I've spent too much time opening 1000 tabs to do these things. Elm is incredible at making it easy to structure data correctly with its nice type system and great package documentation.

`elm-pages` makes SEO head tags, like [Open Graph](https://ogp.me/) and [Twitter Cards](https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started), a first-class type-safe API. The `head` function in a Page Module gets access to your `DataSource` for the page so you can easily use the data you pull in for that page in the pre-rendered head tags.
