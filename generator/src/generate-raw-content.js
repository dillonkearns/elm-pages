module.exports = function(markdown, markup) {
  return `module RawContent exposing (content)

import Dict exposing (Dict)


content : { markdown : List ( List String, { frontMatter : String, body : Maybe String } ), markup : List ( List String, { frontMatter : String, body : Maybe String } ) }
content =
    { markdown = markdown, markup = markup }


markdown : List ( List String, { frontMatter : String, body : Maybe String } )
markdown =
    [ ${markdown.map(toEntry)}
    ]


markup : List ( List String, { frontMatter : String, body : Maybe String } )
markup =
    [ ${markup.map(toEntry)}
    ]`;
};

function toEntry(entry) {
  let fullPath = entry.path
    .replace(/(index)?\.[^/.]+$/, "")
    .split("/")
    .filter(item => item !== "")
    .map(fragment => `"${fragment}"`);
  fullPath.splice(0, 1);

  return `
  ( [${fullPath.join(", ")}]
    , { frontMatter = """${entry.metadata}
""", body = Nothing } )
  `;
}
