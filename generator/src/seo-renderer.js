module.exports = { toString };

function toString(/** @type { SeoTag[] }  */ tags) {
  return tags
    .map((headTag) => {
      if (headTag.type === "head") {
        return appendTag(headTag);
      } else if (headTag.type === "json-ld") {
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
  const tagsString = tagDetails.attributes.map(([name, value]) => {
    return `${name}="${value}"`;
  });
  return `    <${tagDetails.name} ${tagsString.join(" ")} />`;
}

/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */
function appendJsonLdTag(/** @type {JsonLdTag} */ tagDetails) {
  return `<script type="application/ld+json">
${JSON.stringify(tagDetails.contents)}
</script>`;
}
