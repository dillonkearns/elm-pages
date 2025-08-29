# Contributing to `elm-pages`

Hello! 👋

Thanks for checking out the contributing guide for `elm-pages`! Here are some tips and guidelines to make things as smooth as possible.

## Running (and making changes) locally

### Initial setup

```shell
git clone --recurse-submodules https://github.com/dillonkearns/elm-pages.git
cd elm-pages
npm install
npm run build:generator
```

### Use docs for local testing

I use the elm-pages.com site to test out new ideas locally. You can do the same to see if your changes behave the way you want to.

The code for the site lives in the [`examples/docs/`](https://github.com/dillonkearns/elm-pages/tree/master/examples/docs) folder in this repo.

The code for that site is wired up to use the NPM package and Elm package directly in the latest code. So you can make changes to the JS or Elm code and your changes will be reflected when you run the dev server for the elm-pages.com site:

```shell
cd examples/docs
npm install
npm start # runs elm-pages develop with the NPM and Elm package code in your repo
```

### Running against your own local `elm-pages` project

If you want to make changes to the `elm-pages` code generation CLI and try running them against your own local project, you can do so by running these commands:

```shell
cd /path/to/your/local/elm-pages/site
npm install /path/to/cloned/elm-pages
# For example, on my machine I can run: npm install ~/src/github.com/dillonkearns/elm-pages
```

This adds something like this to your `devDependencies`:

```json
    "elm-pages": "file:../..",
```

That has been working very reliably for me, so I can make tweaks and it picks them up right away. I just need to re-run npm start to start the watcher again.

Just be sure to change it back in your local project when you're done experimenting by running `npm install --save-dev elm-pages`.

## Performance Profiling the Webpack Build

You can analyze the webpack performance in the Chrome dev tools performance tab.
It's a lot easier than you might imagine. The steps are:

- Comment out this line: https://github.com/dillonkearns/elm-pages/blob/1fa02c015bf391f0223f0504ee7e8cc7f6f1c60b/generator/src/develop.js#L287
- Run `elm-pages build` (with your dev build)
- Drag and drop the `events.json` file that is emitted by the build into the Chrome performance tab (see https://webpack.js.org/plugins/profiling-plugin/)
- You can use the techniques described here to use bottom-up to understand where most of the time is being spent: https://juliu.is/performant-elm/

## Making pull requests

I really appreciate pull requests, but I always like to start with a discussion first. If you don't mind, please ping me (either on the Elm slack, Twitter, or a Github issue) and start a discussion about your idea before diving in to make a pull request. It's always good to make sure we're on the same page to minimize extra work.
