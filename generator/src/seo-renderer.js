module.exports = { toString, gather };

/** @typedef { { type: 'root'; keyValuePair: [string, string] } } RootTagModifier */

/**
 * @param {( SeoTag | RootTagModifier )[]} tags
 */
function gather(tags) {
  const withoutRootModifiers = tags.flatMap((value) => {
    if (value.type === "root") {
      return [];
    } else {
      return [value];
    }
  });
  const rootModifiers = tags.flatMap((value) => {
    if (value.type === "root") {
      return [value];
    } else {
      return [];
    }
  });
  return {
    rootElement: headTag(rootModifiers),
    headTags: toString(withoutRootModifiers),
  };
}

/**
 * @param {RootTagModifier[]} rootModifiers
 */
function headTag(rootModifiers) {
  const rootModifiersMap = Object.fromEntries(
    rootModifiers.map((modifier) => modifier.keyValuePair)
  );
  if (!("lang" in rootModifiersMap)) {
    rootModifiersMap["lang"] = "en";
  }
  return `<html ${Object.entries(rootModifiersMap)
    .map(pairToAttribute)
    .join(" ")}>`;
}

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
/**
 *
 * @param {[string, string]} param0
 * @returns string
 */
function pairToAttribute([name, value]) {
  return `${name}="${value}"`;
}
