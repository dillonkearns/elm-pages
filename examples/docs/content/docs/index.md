---
title: Quick Start
type: doc
---

## Installing

The easiest way to get set up is to use the starter template. Just go to the [`elm-pages-starter` repo](https://github.com/dillonkearns/elm-pages-starter) and click "Use this template" to fork the repo.

Or clone down the repo:

```
git clone git@github.com:dillonkearns/elm-pages-starter.git
cd elm-pages-starter
npm install
npm start # starts a local dev server using `elm-pages develop`
```

From there, start editing the posts in the `content` folder. You can change the types of content in `src/Metadata.elm`, or render your content using a different renderer (the template uses `elm-explorations/markdown`) by changing [the configuring the document handlers](https://github.com/dillonkearns/elm-pages-starter/blob/2c2241c177cf8e0144af4a8afec0115f93169ac5/src/Main.elm#L70-L80).
