/**
 * @param {string[]} name
 */
function routeParams(name) {
  return name
    .map((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)__?$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      return maybeParam && toFieldName(maybeParam);
    })
    .filter((maybeParam) => maybeParam !== null);
}

/** @typedef { { kind: ('dynamic' | 'optional' | 'required-splat' | 'optional-splat'); name: string } } Segment */

/**
 * @param {string[]} name
 * @returns {Segment[]}
 */
function parseRouteParams(name) {
  return name.flatMap((section) => {
    const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)(_?_?)$/);
    const maybeParam = (routeParamMatch && routeParamMatch[1]) || "TODO";
    const isSplat = maybeParam === "SPLAT";

    // return maybeParam && toFieldName(maybeParam);
    if (routeParamMatch[2] === "") {
      return [];
    } else if (routeParamMatch[2] === "_") {
      if (isSplat) {
        return [
          {
            kind: "required-splat",
            name: toFieldName(maybeParam),
          },
        ];
      } else {
        return [
          {
            kind: "dynamic",
            name: toFieldName(maybeParam),
          },
        ];
      }
    } else if (routeParamMatch[2] === "__") {
      if (isSplat) {
        return [
          {
            kind: "optional-splat",
            name: toFieldName(maybeParam),
          },
        ];
      } else {
        return [
          {
            kind: "optional",
            name: toFieldName(maybeParam),
          },
        ];
      }
    } else {
      throw "Unhandled";
    }
  });
}

/**
 * @param {string[]} name
 * @returns {( Segment | {kind: 'static'; name: string})[]}
 */
function parseRouteParamsWithStatic(name) {
  return name.flatMap((section) => {
    const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)(_?_?)$/);
    const maybeParam = (routeParamMatch && routeParamMatch[1]) || "TODO";
    const isSplat = maybeParam === "SPLAT";

    // return maybeParam && toFieldName(maybeParam);
    if (routeParamMatch[2] === "") {
      return [{ kind: "static", name: maybeParam }];
    } else if (routeParamMatch[2] === "_") {
      if (isSplat) {
        return [
          {
            kind: "required-splat",
            name: toFieldName(maybeParam),
          },
        ];
      } else {
        return [
          {
            kind: "dynamic",
            name: toFieldName(maybeParam),
          },
        ];
      }
    } else if (routeParamMatch[2] === "__") {
      if (isSplat) {
        return [
          {
            kind: "optional-splat",
            name: toFieldName(maybeParam),
          },
        ];
      } else {
        return [
          {
            kind: "optional",
            name: toFieldName(maybeParam),
          },
        ];
      }
    } else {
      throw "Unhandled";
    }
  });
}

/**
 * @param {string[]} name
 * @returns {string}
 */
function routeVariantDefinition(name) {
  return `${routeVariant(name)} { ${parseRouteParams(name).map((param) => {
    switch (param.kind) {
      case "dynamic": {
        return `${param.name} : String`;
      }
      case "optional": {
        return `${param.name} : Maybe String`;
      }
      case "required-splat": {
        return `splat : ( String , List String )`;
      }
      case "optional-splat": {
        return `splat : List String`;
      }
    }
  })} }`;
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
  return `${name.join("__")}`;
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
  parseRouteParams,
  parseRouteParamsWithStatic,
};
