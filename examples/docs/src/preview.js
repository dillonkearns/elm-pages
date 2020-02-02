import {Elm} from './Preview.elm'

const makeImage = ({ name, label, required = true }) => ({
  name,
  label,
  widget: 'object',
  fields: [
    {
      name: 'file',
      label: 'File',
      widget: 'image',
      required: true,
    },
    {
      name: 'alt',
      label: 'Description',
      widget: 'string',
      required: true,
    },
  ]
})

// const collections = [
//   {
//     name: 'pages',
//     label: 'Pages',
//     delete: false,
//     files: [
//       {
//         name: 'home',
//         label: 'Home',
//         file: 'content/index.md',
//         format: 'jsonfrontmatter',
//         fields: [
//           {
//             name: 'template',
//             label: 'Template',
//             widget: 'hidden',
//             default: 'home'
//           },
//           {
//             name: 'sourcePath',
//             label: 'Source Path',
//             widget: 'hidden',
//             default: 'content/index.md',
//           },
//           {
//             name: 'hero',
//             label: 'Top Section',
//             widget: 'object',
//             fields: [
//               makeImage({
//                 name: 'background',
//                 label: 'Background',
//               }),
//               {
//                 name: 'tagline',
//                 label: 'Tagline',
//                 widget: 'string',
//                 required: true
//               }
//             ]
//           },
//           {
//             name: 'signup',
//             label: 'Signup Section',
//             widget: 'object',
//             fields: [
//               {
//                 label: 'Title',
//                 name: 'title',
//                 widget: 'string',
//                 required: true,
//               },
//               {
//                 label: 'Content',
//                 name: 'content',
//                 widget: 'text',
//                 required: true,
//               },
//               {
//                 label: 'Action Network URL',
//                 name: 'url',
//                 widget: 'string',
//                 required: true,
//               },
//             ],
//           },
//           {
//             name: 'cta',
//             label: 'CTA Section',
//             widget: 'object',
//             fields: [
//               {
//                 label: 'Title',
//                 name: 'title',
//                 widget: 'string',
//                 required: true,
//               },
//               {
//                 label: 'Subtitle',
//                 name: 'subtitle',
//                 widget: 'string',
//                 required: false,
//               },
//               {
//                 label: 'Content',
//                 name: 'content',
//                 widget: 'markdown',
//                 required: true,
//               },
//               {
//                 label: 'Action',
//                 name: 'action',
//                 widget: 'string',
//               },
//               {
//                 label: 'Image',
//                 name: 'image',
//                 required: true,
//                 widget: 'image',
//               },
//             ],
//           },
//           {
//             name: 'events',
//             label: 'Events Section',
//             widget: 'object',
//             fields: [
//               makeImage({
//                 name: 'background',
//                 label: 'Background',
//               })
//             ]
//           }
//         ]
//       },
//       {
//         name: 'resources',
//         label: 'Resources',
//         file: 'content/resources.md',
//         fields: [
//           {
//             name: 'template',
//             label: 'Template',
//             widget: 'hidden',
//             default: 'resources'
//           },
//           {
//             name: 'entries',
//             label: 'Entries',
//             widget: 'list',
//             fields: [
//               {
//                 name: 'title',
//                 label: 'Title',
//                 widget: 'string',
//                 required: true,
//               },
//               {
//                 name: 'description',
//                 label: 'Description',
//                 widget: 'text',
//                 required: true,
//               },
//               {
//                 name: 'url',
//                 label: 'URL',
//                 widget: 'string',
//                 required: true,
//               },
//               {
//                 name: 'image',
//                 label: 'Image',
//                 widget: 'image',
//                 required: true,
//               }
//             ]
//           }
//         ]
//       }
//     ]
//   },
//   {
//     name: 'news',
//     label: 'News',
//     folder: 'content/news',
//     create: true,
//     slug: '{{slug}}-{{year}}-{{month}}-{{day}}',
//     extension: 'md',
//     fields: [
//       {
//         name: 'template',
//         label: 'Template',
//         widget: 'hidden',
//         default: 'news-show',
//       },
//       {
//         name: 'title',
//         label: 'Title',
//         widget: 'string',
//         required: true,
//       },
//       {
//         name: 'tags',
//         label: 'Tags',
//         widget: 'list',
//       },
//       makeImage({
//         name: 'image',
//         label: 'Image',
//       }),
//       {
//         name: 'publish_date',
//         label: 'Publish Date',
//         widget: 'date',
//         required: true,
//       },
//       {
//         name: 'summary',
//         label: 'Summary',
//         widget: 'text',
//         required: true,
//       },
//       {
//         name: 'body',
//         label: 'Body',
//         widget: 'markdown',
//         required: true,
//       }
//     ]
//   },
//   {
//     name: 'image-galleries',
//     label: 'Image Galleries',
//     folder: 'content/image-galleries',
//     create: true,
//     slug: '{{slug}}-{{year}}-{{month}}-{{day}} TODO',
//     extension: 'md',
//     fields: [
//       {
//         name: 'template',
//         label: 'Template',
//         widget: 'hidden',
//         default: 'image-gallery',
//       },
//       {
//         name: 'title',
//         label: 'Title',
//         widget: 'string',
//         required: true,
//       },
//       {
//         name: 'images',
//         label: 'Images',
//         widget: 'list',
//         fields: [
//           {
//             name: 'image',
//             label: 'Image',
//             widget: 'image',
//             required: true,
//           },
//           {
//             name: 'description',
//             label: 'Description',
//             widget: 'text',
//             required: true,
//             hint: 'Description of the image, for use on low-connectivity devices and by screen readers.'
//           },
//           {
//             name: 'caption',
//             label: 'Caption',
//             widget: 'text',
//             required: false,
//             hint: 'Commentary on the image, shown below it on screen.'
//           },
//           {
//             name: 'attributionName',
//             label: 'Artist Name',
//             widget: 'string',
//             required: false,
//             hint: 'Name of the photographer or illustrator who created the image, for attribution.'
//           },
//           {
//             name: 'attributionUrl',
//             label: 'Artist URL',
//             widget: 'string',
//             required: false,
//             hint: 'Link to artist website or social media.'
//           },
//         ],
//       },
//     ],
//   },
// ]

const collections = [
    {
    "name": "post",
    "label": "Post",
    "folder": "content/blog",
    "filter": {
        "field": "type",
        "value": "blog"
    },
    "create": true,
    "fields": [
        {
        "label": "Title",
        "name": "title",
        "widget": "string"
        },
        {
        "label": "Publish Date",
        "name": "published",
        "widget": "datetime",
        "timeFormat": false,
        "format": "YYYY-MM-DD"
        },
        {
        "label": "Intro Blurb",
        "name": "description",
        "widget": "text"
        },
        {
        "label": "Is Draft (Hide from index view)",
        "name": "draft",
        "widget": "boolean",
        "default": false,
        "required": false
        },
        {
        "label": "Image",
        "name": "image",
        "widget": "image",
        "required": true
        },
        {
        "label": "Post Author",
        "name": "author",
        "widget": "select",
        "options": [
            "Dillon Kearns"
        ],
        "required": false,
        "default": "Dillon Kearns"
        },
        {
        "label": "Body",
        "name": "body",
        "widget": "markdown"
        },
        {
        "label": "Type",
        "name": "type",
        "widget": "hidden",
        "default": "blog"
        }
    ]
    },
    {
    "name": "page",
    "label": "Page",
    "folder": "content",
    "filter": {
        "field": "type",
        "value": "page"
    },
    "create": true,
    "fields": [
        {
        "label": "Title",
        "name": "title",
        "widget": "string"
        },
        {
        "label": "Body",
        "name": "body",
        "widget": "markdown"
        },
        {
        "label": "Type",
        "name": "type",
        "widget": "hidden",
        "default": "blog"
        }
    ]
    }
]


window.NetlifyCmsApp.registerBackend('file-system', window.FileSystemBackendClass)

// The JSON frontmatter parser that Netlify CMS uses is broken. The YAML frontmatter parser
// works fine but it automatically converts ISO8601 strings to Date instances. Here we
// define a workaround property on the Date prototype so that our Elm JSON decoders can still
// parse them.
Object.defineProperty(Date.prototype, '__NETLIFY_CMS_ISO_8601_STRING_DO_NOT_USE__', {
  get() {
    return this.toISOString()
  }
})

const Preview = (props) => {
  const container = React.createRef()
  const elmApp = React.useRef(null)
  window.React.useEffect(() => {
    if (elmApp.current === null) {
      // httpGet(`/blog/static-http/content.json`).then(function(/** @type JSON */ contentJson) {
        const contentJson = 
          {"body":"\nI'm excited to announce a new feature that brings `elm-pages` solidly into the JAMstack: Static HTTP requests. JAMstack stands for JavaScript, APIs, and Markup. And Static HTTP is all about pulling API data into your `elm-pages` site.\n\nIf you’ve tried `elm-pages`, you may be thinking, \"elm-pages hydrates into a full Elm app... so couldn’t you already make HTTP requests to fetch API data, like you would in any Elm app?\" Very astute observation! You absolutely could.\n\nSo what's new? It all comes down to these key points:\n\n* Less boilerplate\n* Improved reliability\n* Better performance\n\nLet's dive into these points in more detail.\n\n## Less boilerplate\n\nLet's break down how you perform HTTP requests in vanilla Elm, and compare that to how you perform a Static HTTP request with `elm-pages`.\n\n### Anatomy of HTTP Requests in Vanilla Elm\n* Cmd for an HTTP request on init (or update)\n* You receive a `Msg` in `update` with the payload\n* Store the data in `Model`\n* Tell Elm how to handle `Http.Error`s (including JSON decoding failures)\n\n### Anatomy of Static HTTP Requests in `elm-pages`\n* `view` function specifies some `StaticHttp` data, and a function to turn that data into your `view` and `head` tags for that page\n\nThat's actually all of the boilerplate for `StaticHttp` requests!\n\nThere is a lifecycle, because things can still fail. But the entire Static HTTP lifecycle happens *before your users have even requested a page*. The requests are performed at build-time, and that means less boilerplate for you to maintain in your Elm code!\n\n\n### Let's see some code!\nHere's a code snippet for making a StaticHttp request. This code makes an HTTP request to the Github API to grab the current number of stars for the `elm-pages` repo.\n\n```elm\nimport Pages.StaticHttp as StaticHttp\nimport Pages\nimport Head\nimport Secrets\nimport Json.Decode.Exploration as Decode\n\n\nview :\n  { path : PagePath Pages.PathKey\n  , frontmatter : Metadata\n  }\n  ->\n  StaticHttp.Request\n    { view : Model ->\n         View -> { title : String, body : Html Msg }\n    , head : List (Head.Tag Pages.PathKey)\n    }\nview page =\n  (StaticHttp.get\n    (Secrets.succeed\n    \"https://api.github.com/repos/dillonkearns/elm-pages\")\n    (Decode.field \"stargazers_count\" Decode.int)\n  )\n  |> StaticHttp.map\n    (\\starCount ->\n      { view =\n        \\model renderedMarkdown ->\n          { title = \"Landing Page\"\n          , body =\n            [ header starCount\n            , pageView model renderedMarkdown\n            ]\n          }\n      , head = head starCount\n      }\n    )\n\n\nhead : Int -> List (Head.Tag Pages.PathKey)\nhead starCount =\n  Seo.summaryLarge\n    { canonicalUrlOverride = Nothing\n    , siteName = \"elm-pages - \" \n       ++ String.fromInt starCount\n       ++ \" GitHub Stars\"\n    , image =\n      { url = images.iconPng\n      , alt = \"elm-pages logo\"\n      , dimensions = Nothing\n      , mimeType = Nothing\n      }\n    , description = siteTagline\n    , locale = Nothing\n    , title = \"External Data Example\"\n    }\n    |> Seo.website\n```\n\nThe data is baked into our built code, which means that the star count will only update when we trigger a new build. This is a common JAMstack technique. Many sites will trigger builds periodically to refresh data. Or better yet, use a webhook to trigger new builds whenever new data is available (for example, if you add a new blog post or a new page using a service like Contentful).\n\nNotice that this app's `Msg`, `Model`, and `update` function are not involved in the process at all! It's also worth noting that we are passing that data into our `head` function, which allows us to use it in our `<meta>` tags for the page.\n\nThe `StaticHttp` functions are very similar to Elm libraries\nyou've likely used already, such as `elm/json` or `elm/random`.\nIf you don't depend on any StaticHttp data, you use `StaticHttp.succeed`,\nsimilar to how you might use `Json.Decode.succeed`, `Random.constant`,\netc.\n\n\n```elm\nimport Pages.StaticHttp as StaticHttp\n\n\nStaticHttp.succeed\n  { view =\n    \\model renderedMarkdown ->\n      { title = \"Landing Page\"\n      , body =\n        [ header\n        , pageView model renderedMarkdown\n        ]\n      }\n  , head = head\n  }\n```\n\nThis is actually the same as our previous example that had a `StaticHttp.request`, except that it doesn't make a request or have the\nstargazer count data.\n\n### Secure Secrets\nA common pattern is to use environment variables in your local environment or your CI environment in order to securely manage\nauth tokens and other secure data. `elm-pages` provides an API for accessing this data directly from your environment variables.\nYou don't need to wire through any flags or ports, simply use the [`Pages.Secrets` module (see the docs for more info)](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Pages-Secrets). It will take care of masking the secret data for you\nso that it won't be accessible in the bundled assets (it's just used to perform the requests during the build step, and then\nit's masked in the production assets).\n\n### The Static HTTP Lifecycle\nIf you have a bad auth token in your URL, or your JSON decoder fails, then that code will never run for your `elm-pages` site. Instead, you'll get a friendly `elm-pages` build-time error telling you exactly what the problem was and where it occurred (as you're familiar with in Elm).\n\n![StaticHttp build error](/images/static-http-error.png)\n\nThese error messages are inspired by Elm's famously helpful errors. They're designed to point you in the right direction, and provide as much context as possible.\n\nWhich brings us to our next key point...\n\n## Improved reliability\nStatic HTTP requests are performed at build-time. Which means that if you have a problem with one of your Static HTTP requests, *your users will never see it*. Even if a JSON decoder fails, `elm-pages` will report back the decode failure and wait until its fixed before it allows you to create your production build.\n\nYour API might go down, but your Static HTTP requests will always be up (assuming your site is up). The responses from your Static requests are baked into the static files for your `elm-pages` build. If there is an API outage, you of course won't be able to rebuild your site with fresh data from that API. But you can be confident that, though your build may break, your site will always have a working set of Static HTTP data.\n\nCompare this to an HTTP request in a vanilla Elm app. Elm can guarantee that you've handled all error cases. But you still need to handle the case where you have a bad HTTP response, or a JSON decoder fails. That's the best that Elm can do because it can't guarantee anything about the data you'll receive at runtime. But `elm-pages` *can* make guarantees about the data you'll receive! Because it introduces a new concept of data that you get a snapshot of during your build step. `elm-pages` guarantees that this frozen moment of time has no problems before the build succeeds, so we can make even stronger guarantees than we can with plain Elm.\n\n## Better performance\nThe StaticHttp API also comes with some significant performance boosts. StaticHttp data is just a static JSON file for each page in your `elm-pages` site. That means that:\n\n* No waiting on database queries to fetch API data\n* Your site, including API responses, is just static files so it can be served through a blazing-fast CDN (which serves files from the nearest server in the user's region)\n* Scaling is cheap and doesn't require an Ops team\n* `elm-pages` intelligently prefetches the Static HTTP data for a page when you're likely to navigate to that page, so page loads are instant and there's no spinner waiting to load that initial data\n* `elm-pages` optimizes your `StaticHttp` JSON data, stripping out everything but what you use in your JSON decoder\n\n### JSON Optimization\nThe JSON optimization is made possible by a JSON parsing library created by Ilias Van Peer. Here's the pull request where he introduced the JSON optimization functionality: [github.com/zwilias/json-decode-exploration/pull/9](https://github.com/zwilias/json-decode-exploration/pull/9).\n\nLet's take our Github API request as an example. Our Github API request from our previous code snippet ([https://api.github.com/repos/dillonkearns/elm-pages](https://api.github.com/repos/dillonkearns/elm-pages)) has a payload of 5.6KB (2.4KB gzipped). That size of the optimized JSON drops down to about 3% of that.\n\nYou can inspect the network tab on this page and you'll see something like this:\n\n![StaticHttp content request](/images/static-http-content-requests.png)\n\nIf you click on Github API link above and compare it, you'll see that it's quite a bit smaller! It just has the one field that we grabbed in our JSON decoder.\n\nThis is quite nice for privacy and security purposes as well because any personally identifying information that might be included in an API response you consume won't show up in your production bundle (unless you were to explicitly include it in a JSON decoder).\n\n### Comparing StaticHttp to other JAMstack data source strategies\nYou may be familiar with frameworks like Gatsby or Gridsome which also allow you to build data from external sources into your static site. Those frameworks, however, use a completely different approach, [using a GraphQL layer to store data from those data sources](https://www.gatsbyjs.org/docs/page-query/), and then looking that data up in GraphQL queries from within your static pages.\n\n\nThis approach makes sense for those frameworks. But since `elm-pages` is built on top of a language that already has an excellent type system, I wanted to remove that additional layer of abstraction and provide a simpler way to consume static data. The fact that Elm functions are all deterministic (i.e. given the same inputs they will always have the same outputs) opens up exciting new approaches to these problems as well. One of Gatsby's stated reasons for encouraging the use of their GraphQL layer is that it allows you to have your data all in one place. But the `elm-pages` StaticHttp API gives you similar benefits, using familiar Elm techniques like `map`, `andThen`, etc to massage your data into the desired format.\n\n## Future plans\n\nI'm looking forward to exploring more possibilities for using static data in `elm-pages`. Some things I plan to explore are:\n\n* Programatically creating pages using the Static HTTP API\n* Configurable image optimization (including producing multiple dimensions for `srcset`s) using a similar API\n* Optimizing the page metadata that is included for each page (i.e. code splitting) by explicitly specifying what metadata the page depends on using an API similar to StaticHttp\n\n## Getting started with StaticHttp\n\nYou can [take a look at this an end-to-end example app that uses the new `StaticHttp` library](https://github.com/dillonkearns/elm-pages/blob/master/examples/external-data/src/Main.elm) to get started.\n\nOr just use the [`elm-pages-starter` repo](https://github.com/dillonkearns/elm-pages-starter) and start building something cool! Let me know your thoughts on Slack, I'd love to hear from you! Or continue the conversation on Twitter!\n\n<Oembed url=\"https://twitter.com/dillontkearns/status/1214238507163471872\" />","staticData":{"{\"method\":\"GET\",\"url\":\"https://api.github.com/repos/dillonkearns/elm-pages\",\"headers\":[],\"body\":{\"type\":\"empty\"}}":"{\"id\":198527910,\"node_id\":\"MDEwOlJlcG9zaXRvcnkxOTg1Mjc5MTA=\",\"name\":\"elm-pages\",\"full_name\":\"dillonkearns/elm-pages\",\"private\":false,\"owner\":{\"login\":\"dillonkearns\",\"id\":1384166,\"node_id\":\"MDQ6VXNlcjEzODQxNjY=\",\"avatar_url\":\"https://avatars3.githubusercontent.com/u/1384166?v=4\",\"gravatar_id\":\"\",\"url\":\"https://api.github.com/users/dillonkearns\",\"html_url\":\"https://github.com/dillonkearns\",\"followers_url\":\"https://api.github.com/users/dillonkearns/followers\",\"following_url\":\"https://api.github.com/users/dillonkearns/following{/other_user}\",\"gists_url\":\"https://api.github.com/users/dillonkearns/gists{/gist_id}\",\"starred_url\":\"https://api.github.com/users/dillonkearns/starred{/owner}{/repo}\",\"subscriptions_url\":\"https://api.github.com/users/dillonkearns/subscriptions\",\"organizations_url\":\"https://api.github.com/users/dillonkearns/orgs\",\"repos_url\":\"https://api.github.com/users/dillonkearns/repos\",\"events_url\":\"https://api.github.com/users/dillonkearns/events{/privacy}\",\"received_events_url\":\"https://api.github.com/users/dillonkearns/received_events\",\"type\":\"User\",\"site_admin\":false},\"html_url\":\"https://github.com/dillonkearns/elm-pages\",\"description\":\"A statically typed site generator for Elm.\",\"fork\":false,\"url\":\"https://api.github.com/repos/dillonkearns/elm-pages\",\"forks_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/forks\",\"keys_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/keys{/key_id}\",\"collaborators_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/collaborators{/collaborator}\",\"teams_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/teams\",\"hooks_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/hooks\",\"issue_events_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/issues/events{/number}\",\"events_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/events\",\"assignees_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/assignees{/user}\",\"branches_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/branches{/branch}\",\"tags_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/tags\",\"blobs_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/git/blobs{/sha}\",\"git_tags_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/git/tags{/sha}\",\"git_refs_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/git/refs{/sha}\",\"trees_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/git/trees{/sha}\",\"statuses_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/statuses/{sha}\",\"languages_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/languages\",\"stargazers_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/stargazers\",\"contributors_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/contributors\",\"subscribers_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/subscribers\",\"subscription_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/subscription\",\"commits_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/commits{/sha}\",\"git_commits_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/git/commits{/sha}\",\"comments_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/comments{/number}\",\"issue_comment_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/issues/comments{/number}\",\"contents_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/contents/{+path}\",\"compare_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/compare/{base}...{head}\",\"merges_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/merges\",\"archive_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/{archive_format}{/ref}\",\"downloads_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/downloads\",\"issues_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/issues{/number}\",\"pulls_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/pulls{/number}\",\"milestones_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/milestones{/number}\",\"notifications_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/notifications{?since,all,participating}\",\"labels_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/labels{/name}\",\"releases_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/releases{/id}\",\"deployments_url\":\"https://api.github.com/repos/dillonkearns/elm-pages/deployments\",\"created_at\":\"2019-07-24T00:27:26Z\",\"updated_at\":\"2020-02-02T15:38:51Z\",\"pushed_at\":\"2020-02-02T19:41:29Z\",\"git_url\":\"git://github.com/dillonkearns/elm-pages.git\",\"ssh_url\":\"git@github.com:dillonkearns/elm-pages.git\",\"clone_url\":\"https://github.com/dillonkearns/elm-pages.git\",\"svn_url\":\"https://github.com/dillonkearns/elm-pages\",\"homepage\":\"https://elm-pages.com\",\"size\":12816,\"stargazers_count\":176,\"watchers_count\":176,\"language\":\"Elm\",\"has_issues\":true,\"has_projects\":true,\"has_downloads\":true,\"has_wiki\":true,\"has_pages\":false,\"forks_count\":19,\"mirror_url\":null,\"archived\":false,\"disabled\":false,\"open_issues_count\":16,\"license\":{\"key\":\"bsd-3-clause\",\"name\":\"BSD 3-Clause \\\"New\\\" or \\\"Revised\\\" License\",\"spdx_id\":\"BSD-3-Clause\",\"url\":\"https://api.github.com/licenses/bsd-3-clause\",\"node_id\":\"MDc6TGljZW5zZTU=\"},\"forks\":19,\"open_issues\":16,\"watchers\":176,\"default_branch\":\"master\",\"temp_clone_token\":null,\"network_count\":19,\"subscribers_count\":9}"}}
        console.log('contentJson', contentJson); // TODO fetch real data here with http request
        
      console.log('container', container)
      elmApp.current = Elm.Preview.init({
        node: container.current,
        flags: {
          contentJson: {
            body: props.entry.get('data').toJS().body,
            staticData: contentJson.staticData
          },
          preview: {
            path: props.entry.get('path'),
            body: props.entry.get('data').toJS().body,
            frontmatter: JSON.stringify(props.entry.get('data').toJS()),
          }
        }
      })
    // });
    }
    // else {
    //   elmApp.current.ports.updateContents.send(props.entry.get('data').toJS())
    // }
  }, [props.entry.get('data')])

  return window.React.createElement('div', {
    ref: container,
  })
}

collections.forEach((collection) => {
  if (collection.files) {
    collection.files.forEach((file) => {
      window.NetlifyCmsApp.registerPreviewTemplate(file.name, Preview)
    })
  } else {
    window.NetlifyCmsApp.registerPreviewTemplate(collection.name, Preview)
  }
})

window.NetlifyCmsApp.init({
  config: {
    backend: window.location.hostname === 'localhost' ? {
      name: 'file-system',
      api_root: 'http://localhost:3001/api',
    } : {
      name: 'github',
      repo: 'dillonkearns/elm-pages-netlify-cms-starter',
      branch: 'master',
    },
    media_folder: 'images',
    public_folder: '/images',
    site_url: window.location.origin,
    display_url: window.location.origin,
    load_config_file: false,
    collections: collections,
  }
})


function httpGet(/** @type string */ theUrl) {
  return new Promise(function(resolve, reject) {
    const xmlHttp = new XMLHttpRequest();
    xmlHttp.onreadystatechange = function() {
        if (xmlHttp.readyState == 4 && xmlHttp.status == 200)
            resolve(JSON.parse(xmlHttp.responseText));
    }
    xmlHttp.onerror = reject;
    xmlHttp.open("GET", theUrl, true); // true for asynchronous
    xmlHttp.send(null);
  })
}
