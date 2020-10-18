const elmPagesVersion = "TODO";

module.exports = { toString };

function toString(/** @type { SeoTag[] }  */ tags) {
  //   appendTag({
  //     type: "head",
  //     name: "meta",
  //     attributes: [
  //       ["name", "generator"],
  //       ["content", `elm-pages v${elmPagesVersion}`],
  //     ],
  //   });

  const generatorTag /** @type { HeadTag } */ = {
    type: "head",
    name: "meta",
    attributes: [
      ["name", "generator"],
      ["content", `elm-pages v${elmPagesVersion}`],
    ],
  };
  //   tags.concat([generatorTag]);

  return tags
    .map((rawValue) => {
      const type = rawValue.tag;
      const headTag = rawValue.args[0];
      if (type === "Tag") {
        return appendTag(headTag);
      } else if (headTag.type === "StructuredData") {
        return appendJsonLdTag(headTag);
      } else {
        throw new Error(`Unknown tag type ${JSON.stringify(headTag)}`);
      }
    })
    .join("\n");
}

/** @typedef {HeadTag | JsonLdTag} SeoTag */

/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
function appendTag(/** @type {HeadTag} */ tagDetails) {
  //   const meta = document.createElement(tagDetails.name);
  const tagsString = tagDetails.attributes.map(([name, value]) => {
    // meta.setAttribute(name, value);
    return `${name}="${value}"`;
  });
  return `    <${tagDetails.name} ${tagsString.join(" ")} />`;
  //   document.getElementsByTagName("head")[0].appendChild(meta);
}

/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */
function appendJsonLdTag(/** @type {JsonLdTag} */ tagDetails) {
  //   let jsonLdScript = document.createElement("script");
  //   jsonLdScript.type = "application/ld+json";
  //   jsonLdScript.innerHTML = JSON.stringify(tagDetails.contents);
  //   document.getElementsByTagName("head")[0].appendChild(jsonLdScript);
  return `<script type="application/ld+json">
${JSON.stringify(tagDetails.contents)}
</script>`;
}
