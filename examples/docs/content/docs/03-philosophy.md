# The elm-pages philosophy

## Derive Features From Building Blocks

Many frameworks provide features like

- Markdown parsing
- Special frontmatter directives
- RSS reader generation.

You can do all those things with `elm-pages`, but using the core building blocks

- The DataSources API lets you read from a file, parse frontmatter, and more. `elm-pages` helps you get the data.
- The data you get from any of those data sources is just typed Elm data. You decide what it means and how to use it.

The goal of `elm-pages` is to get nicely typed data from the right sources (HTTP, files, structured formats like JSON, markdown, etc.), and get that data to the right places in order to build an optimized site with good SEO.
