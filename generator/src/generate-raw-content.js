module.exports = function(markdown, markup) {
  return `module RawContent exposing (content)

import Dict exposing (Dict)


content : List ( List String, { extension: String, frontMatter : String, body : Maybe String } )
content =
    [ ${markdown.concat(markup).map(toEntry)}
    ]
    `;
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
""" , body = Nothing
    , extension = "${entry.extension}"
    } )
  `;
}
