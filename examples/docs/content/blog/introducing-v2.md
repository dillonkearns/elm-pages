---
{
  "author": "Dillon Kearns",
  "title": "Introducing elm-pages 2.0",
  "description": "This release represents a huge improvement for elm-pages in terms of features, developer experience, and performance.",
  "image": "v1627861555/elm-pages/article-covers/photo-1471107340929-a87cd0f5b5f3_mczjfg.jpg",
  "published": "2021-08-01",
}
---

This release represents a huge improvement for `elm-pages` in terms of features, developer experience, and performance. It introduces a completely custom dev server with absolutely no webpack, that gives you hot module replacement as you change Elm code and data (like markdown files)! It also replaces some specific features with more flexible and universal building blocks, opening up a lot of new use cases, and using fewer core concepts to enable more possibilities. And all that with the type-safety and robust feedback we've come to expect in the Elm ecosystem.

## Features

Before this release, the `StaticHttp` API let you pull in data and use it in pre-rendered pages and their SEO tags. That is, you could present data that is validated at build-time, with no loading spinners or error states. If there's a problem, you get a build error and can fix it before a user sees it.

In v2, this API has been renamed to `BackendTask` to reflect the broader range of uses. Not only can you pull in data from more places than just API requests, but you can use that data in more places as well. If this concept was an important feature before v2, after the v2 release you can consider it to be the fundamental building block of the entire `elm-pages` platform.

### Doubling down on BackendTasks

One of the biggest features that was missing before v2 was the ability to use external data to determine pre-rendered pages. In v1, adding new files to the `content/` folder (usually markdown files) was the only way to create a new page. This limitation meant that you couldn't, for example, use a CMS (Content Management System) to host your blog posts or other pages in an external system, and then use that external data to create a page for each entry.

With `elm-pages` v2, you can use any BackendTask to determine the pre-rendered pages for a Route. For example, let's take a look at how this blog post right here is rendered.

To create a blog post, we could run `elm-pages add Blog.Slug_`. Each section of the Page Module's name represents a segment of the URL. The trailing `_` means that slug is dynamic. You may have seen routes notated like this: `/blog/:slug`. So running this command scaffolds a module which `elm-pages` v2's file-based routing will use to render pages like `/blog/introducing-v2`.

Because these blog posts are just local files in this blog, we can use `BackendTask.Glob` to enumerate all the pages we want for our `/blog/:slug` Route.

```elm
module Page.Blog.Slug_ exposing (Data, Model, Msg, page)

import BackendTask exposing (BackendTask)
import BackendTask.Glob as Glob

type alias RouteParams =
    { slug : String }


page : Page RouteParams Data
page =
    Page.preRender
        { data = data
        , head = head
        , routes = routes
        }
        |> Page.buildNoState { view = view }


routes : BackendTask (List RouteParams)
routes =
    Glob.succeed RouteParams
        |> Glob.match (Glob.literal "content/blog/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
        |> Glob.toBackendTask
```

`elm-pages` doesn't care what the source of the data is for the pre-rendered routes, though - it only cares that you have a `BackendTask (List RouteParams)`.

If we wanted to migrate our blog posts over to an external CMS and fetch the blog posts with HTTP, then we would just swap out that `BackendTask` for different one:

```elm
import OptimizedDecoder as Decode
import BackendTask.Http
import Pages.Secrets


type alias RouteParams =
    { slug : String }


routes : BackendTask (List RouteParams)
routes =
    BackendTask.Http.get
        (Pages.Secrets.succeed ("https://api.my-cms.com/all-blog-posts"))
        (Decode.list (blogPostDecoder |> Decode.map .slug |> Decode.map RouteParams))
```

### BackendTask.Port

The core built-in `BackendTask` modules let you pull in

- Local files ([`BackendTask.File`](BackendTask-File)), including [decoding frontmatter](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask-File#onlyFrontmatter)
- HTTP requests ([`BackendTask.Http`](BackendTask-Http))
- Globs, i.e. listing out local files based on a pattern like `content/*.txt` ([`BackendTask.Glob`](BackendTask-Glob))
- Hardcoded data (`BackendTask.succeed "Hello!"`)
- Or any combination of the above, using `BackendTask.map2`, `BackendTask.andThen`, or other combining/continuing helpers from this module

If that isn't enough to get you the data you need to pull in to your site, then there's an additional module that lets you build your own custom `BackendTask`.

[`BackendTask.Port`](BackendTask-Port) lets you decode JSON data that you call from custom NodeJS functions. As with any `BackendTask`, you get this data in the build step and then it gets built in to your site, so these NodeJS functions, HTTP requests, file reads, etc. are not happening when a user opens a page in your live site that you built with `elm-pages build`.

```elm
data : BackendTask String
data =
    BackendTask.Port.get "environmentVariable"
        (Json.Encode.string "EDITOR")
        Decode.string
```

```javascript
const kleur = require("kleur");
// this example uses kleur to add ANSI color codes
// They're just strings, so you can use your preferred tool
// or skip it altogether if you don't care about color output

module.exports = {
  environmentVariable: async function (name) {
    const result = process.env[name];
    if (result) {
      return result;
    } else {
      throw `No environment variable called ${kleur
        .yellow()
        .underline(name)}\n\nAvailable:\n\n${Object.keys(process.env).join(
        "\n"
      )}`;
    }
  },
};
```

There are a few benefits to this functionality:

- It gives you the building block to add any BackendTask you need, like calling shell scripts for example
- If you throw an error, you get a nice error message when you run `elm-pages build` and in your dev server
- You can leverage a huge ecosystem of tools, including ones with native dependencies, in the NPM ecosystem - for example, you could use `sharp` to get an image's width/height from your filesystem
- You can shave off computation and data from the final site so users get a snappier experience - one of the core principles of JAMstack. For example, I like using `shiki` to pull in all the syntax highlighting grammars from VS Code at build time, and distilling it down to the tokenized output that has already been parsed by the time the browser loads it (pulling in every VS Code language grammar to your bundle would not be viable!)

## Developer Experience

### More flexible building blocks

Now a page is as simple as you need it to be. The concept of Metadata in v1 often led to markdown files like this:

```markdown
---
title: Blog Posts
type: blog-index-page
---
```

Just an empty markdown file with some frontmatter, so the page could be decoded as Metadata. Then using a `case` expression, you could render your blog view within your main Elm view if it was the blog-index-page.

`elm-pages` 2.0 uses a pull-based approach. You can define a Page Module and just use it to render an Elm view (or a mini Elm app with its own Msg and update). Or you can pull in metadata from all blog posts if that's what you need. It's up to you. The core building blocks let you pull in data, and it's up to you to define where to get the data from and what to do with it.

## Performance

### No more webpack

`elm-pages` v1 was built on top of Webpack. It used a Webpack plugin to run Puppeteer and pre-render all the pages. This was brittle and was a major bottleneck for performance.

v2 has removed Webpack, as well as many other NPM dependencies. The dev server is completely custom tailored to compile your `elm-pages` app, give you Elm compiler error overlays in the dev server, as well as `BackendTask` error overlays. And it even does hot module replacement for the `BackendTask`s your page depends on. For example, if you have a `BackendTask` to list out every blog post marked with a particular tag in the frontmatter, if you save a markdown file and add or remove a tag, it will be instantly reflected when you are viewing the page in the dev server.

I did a lot of performance tuning as part of this release, and for the sites that I've upgraded I'm seeing build times in the seconds rather than minutes. If you upgrade your site from v1 to v2, I'd love to hear about your before/after performance!

## What's on the horizon

One of the core changes under the hood in v2 is that everything is built one page at a time. That's central to how the dev server performance was optimized to quickly render and hot reload pages and their data.

This new architecture under the hood is also what powers some experimental functionality that will be the focus of the next `elm-pages` milestone: serverless rendering. Serverless functions let you run JavaScript code with minimal infrastructure setup, and respond to an HTTP request. This is essentially exactly what the dev server is doing, so it's not a big leap from that to rendering pages at request-time instead of pre-rendering them at build-time.

Pre-rendering pages is still ideal in cases where you have the data you need ahead of time, but in some cases you may want to pull in data on-demand, or even use request headers when serving up the page. For example, you could use an authentication header to verify that a user is logged in, and do a redirect or serve up the user's page depending on the auth check. One of the challenges with traditional Jamstack sites is content that is user-specific, and this functionality can open up some use cases in this area.

Stay tuned for more on this front. For now, give the new v2 a try! You can set up a new app by running `npx elm-pages@latest init my-app`. You can also [read more in the elm-pages docs](https://elm-pages.com/docs), and check out [the `elm-pages` package documentation](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest). If you make a shiny new v2 site, submit it to [the showcase](https://elm-pages.com/showcase), I'd love to see what you build!
