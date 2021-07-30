# Getting Started

You can create a fresh `elm-pages` project with the `init` command.

```shell
npx elm-pages init my-project
```

This will create a new project in `my-project/`. You can then start a dev server and add new routes using these CLI commands.

## CLI commands

- `elm-pages dev` - Start the `elm-pages` dev server
- `elm-pages add Slide.Number_` Generate scaffolding for a new Page Template
- `elm-pages build` - generate a full production build in the `dist/` folder. You'll often want to use a CDN service like [Netlify](http://netlify.com/) or [Vercel](https://vercel.com/) to deploy these generated static files

## The dev server

`elm-pages dev` gives you a dev server with hot module replacement built-in. It even reloads your `DataSource`s any time you change them.
