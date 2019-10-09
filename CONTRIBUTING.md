# Contributing to `elm-pages`

Hello! 👋

Thanks for checking out the contributing guide for `elm-pages`! Here are some tips and guidelines to make things as smooth as possible.


## Running (and making changes) locally

I use the elm-pages.com site to test out new ideas locally. You can do the same to see if your changes behave the way you want to.

The code for the site lives in the [`examples/docs/`](https://github.com/dillonkearns/elm-pages/tree/master/examples/docs) folder in this repo.

The code for that site is wired up to use the NPM package and Elm package directly in the latest code. So you can make changes to the JS or Elm code and your changes will be reflected when you run the dev server for the elm-pages.com site:

```shell
cd examples/docs
npm start # runs elm-pages develop with the NPM and Elm package code in your repo
```

## Making pull requests

I really appreciate pull requests, but I always like to start with a discussion first. If you don't mind, please ping me (either on the Elm slack, Twitter, or a Github issue) and start a discussion about your idea before diving in to make a pull request. It's always good to make sure we're on the same page to minimize extra work.
