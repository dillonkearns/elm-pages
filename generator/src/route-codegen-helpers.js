/**
 * @param {string[]} name
 */
function routeParams(name) {
  return name
    .map((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)_$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      return maybeParam && toFieldName(maybeParam);
    })
    .filter((maybeParam) => maybeParam !== null);
}

/**
 * @param {string[]} name
 */
function routeVariantDefinition(name) {
  return `${routeVariant(name)} { ${routeParams(name).map(
    (param) => `${param} : String`
  )} }`;
}

/**
 * @param {string[]} name
 */
function paramsRecord(name) {
  return `{ ${routeParams(name).map((param) => `${param} : String`)} }`;
}

/**
 * @param {string[]} name
 */
function routeVariant(name) {
  return `Route${name.join("__")}`;
}

/**
 * @param {string } name
 */
function toFieldName(name) {
  return name.toLowerCase();
}

module.exports = {
  routeParams,
  routeVariantDefinition,
  routeVariant,
  toFieldName,
  paramsRecord,
};
