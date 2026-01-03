# Getting Started

You can create a fresh `elm-pages` project with the `init` command.

```shell
npx elm-pages init my-project
cd my-project
npm install
npx elm-pages dev
```

This creates a new project in `my-project/` and starts the dev server. You can then add new routes using the CLI commands below.

You can get the `npx` command by installing [node](https://nodejs.org). `elm-pages` supports all and only [supported release lines](https://github.com/nodejs/release#release-schedule) of node.

## Lamdera

[`elm-pages` Scripts](/docs/elm-pages-scripts) can run with the Elm compiler if the Lamdera compiler isn't installed. However, builds (`elm-pages build`) and the dev server (`elm-pages dev`) require the Lamdera compiler to be installed.

You can [install Lamdera with these instructions](https://dashboard.lamdera.app/docs/download).

`elm-pages` Routes use the lamdera compiler, which is a superset of the Elm compiler with some extra functionality to automatically serialize Elm types to Bytes.

## Debugging Lamdera Errors

Sometimes Lamdera will give compiler errors due to corrupted dependency cache. These messages will display a note at the bottom:

```
-- PROBLEM BUILDING DEPENDENCIES ---------------

...


Note: Sometimes `lamdera reset` can fix this problem by rebuilding caches, so
give that a try first.
```

Be sure to use `lamdera reset` to reset the caches for these cases. See more info about that in the Lamdera docs: https://dashboard.lamdera.app/docs/ides-and-tooling#problem-corrupt-caches

## CLI commands

- `elm-pages dev` - Start the `elm-pages` dev server
- `elm-pages run AddRoute Slide.Number_` Generate scaffolding for a new Page Module (learn about running scripts and modifying the scaffolding script in the [Scaffolding](/docs/elm-pages-scripts) section)
- `elm-pages build` - generate a full production build in the `dist/` folder. You'll often want to use a CDN service like [Netlify](http://netlify.com/) or [Vercel](https://vercel.com/) to deploy these generated static files

## The dev server

`elm-pages dev` gives you a dev server with hot module replacement built in. It even reloads your `BackendTask`s any time you change them.
