module.exports = { gather };

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
    .flatMap((headTag) => {
      if (headTag.type === "head") {
        return [appendTag(headTag)];
      } else if (headTag.type === "json-ld") {
        return [appendJsonLdTag(headTag)];
      } else if (headTag.type === "stripped") {
        console.warn(
          `WARNING: Head.nonLoadingTag value ignored because it used a loading tag: ${headTag.message}`
        );
        return [];
      } else {
        throw new Error(`Unknown tag type ${JSON.stringify(headTag)}`);
      }
    })
    .join("");
}

/** @typedef {HeadTag | JsonLdTag | StrippedTag} SeoTag */

/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
function appendTag(/** @type {HeadTag} */ tagDetails) {
  const tagsString = tagDetails.attributes.map(([name, value]) => {
    return pairToAttribute([name, value]);
  });
  return `    <${tagDetails.name} ${tagsString.join(" ")} />`;
}

/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */
/** @typedef {{ message: string; type: 'stripped' }} StrippedTag */

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
  return `${name}="${quoteattr(value)}"`;
}

function quoteattr(s, preserveCR) {
  preserveCR = preserveCR ? "&#13;" : "\n";
  return (
    ("" + s) /* Forces the conversion to string. */
      .replace(/&/g, "&amp;") /* This MUST be the 1st replacement. */
      .replace(/'/g, "&apos;") /* The 4 other predefined entities, required. */
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      /*
        You may add other replacements here for HTML only 
        (but it's not necessary).
        Or for XML, only if the named entities are defined in its DTD.
        */
      .replace(/\r\n/g, preserveCR) /* Must be before the next replacement. */
      .replace(/[\r\n]/g, preserveCR)
  );
}
