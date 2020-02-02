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
      httpGet(`/blog/static-http/content.json`).then(function(/** @type JSON */ contentJson) {
        console.log('contentJson', contentJson); // TODO fetch real data here with http request
        
      console.log('container', container)
      try {
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
    } catch {
      // TODO find how to avoid using this catch
    }
    });
    // TODO find how to do a smooth update (or maybe it's not necessary if it's just as smooth without it)
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
