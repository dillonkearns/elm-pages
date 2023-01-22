/**
 * @param {string[]} name
 */
export function routeParams(name) {
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
export function parseRouteParams(name) {
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
export function parseRouteParamsWithStatic(name) {
  return name.flatMap((section) => {
    const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)(_?_?)$/);
    const maybeParam = (routeParamMatch && routeParamMatch[1]) || "TODO";
    const isSplat = maybeParam === "SPLAT";

    // return maybeParam && toFieldName(maybeParam);
    if (routeParamMatch[2] === "") {
      if (maybeParam === "Index") {
        return [];
      } else {
        return [{ kind: "static", name: maybeParam }];
      }
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
export function routeVariantDefinition(name) {
  const newLocal = parseRouteParams(name);
  if (newLocal.length == 0) {
    return routeVariant(name);
  } else {
    return `${routeVariant(name)} { ${newLocal.map((param) => {
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
}

/**
 * @param {string[]} name
 * @returns {string}
 */
export function toPathPattern(name) {
  return (
    "/" +
    parseRouteParamsWithStatic(name)
      .map((param) => {
        switch (param.kind) {
          case "static": {
            return camelToKebab(param.name);
          }
          case "dynamic": {
            return `:${param.name}`;
          }
          case "optional": {
            return `[:${param.name}]`;
          }
          case "required-splat": {
            return `TODO_SPLAT`;
          }
          case "optional-splat": {
            return `TODO_SPLAT`;
          }
        }
      })
      .join("/")
  );
}
/**
 * @param {string[]} name
 * @returns {string[]}
 */
export function toPathPatterns(name) {
  const segments = parseRouteParamsWithStatic(name);

  const lastSegment = segments[segments.length - 1];
  const allButLast = segments.slice(0, segments.length - 1);
  if (lastSegment && lastSegment.kind === "optional") {
    return [
      joinPath(newHelper(allButLast)),
      joinPath(newHelper(allButLast).concat(`:${lastSegment.name}`)),
    ];
  } else {
    return [joinPath(newHelper(segments))];
  }
}

/**
 * @param {string[]} segments
 */
export function joinPath(segments) {
  const joined = segments.join("/");
  if (joined.startsWith("/")) {
    return joined;
  } else {
    return "/" + joined;
  }
}

/**
 * @return {string[]}
 */
export function newHelper(segments) {
  return segments.map((param) => {
    switch (param.kind) {
      case "static": {
        return camelToKebab(param.name);
      }
      case "dynamic": {
        return `:${param.name}`;
      }
      case "optional": {
        return `[:${param.name}]`;
      }
      case "required-splat": {
        return `*`;
      }
      case "optional-splat": {
        return `*`;
      }
    }
  });
  // .join("/");
}

/**
 * @param {string[]} name
 * @returns {string}
 */
export function toElmPathPattern(name) {
  const parsedSegments = parseRouteParamsWithStatic(name);

  const foundEndings = parsedSegments.flatMap((segment) => {
    switch (segment.kind) {
      case "static": {
        return [];
      }
      case "dynamic": {
        return [];
      }
      case "optional": {
        return [`( Pages.Internal.RoutePattern.Optional "${segment.name}" )`];
      }
      case "required-splat": {
        return [`Pages.Internal.RoutePattern.RequiredSplat`];
      }
      case "optional-splat": {
        return [`Pages.Internal.RoutePattern.OptionalSplat`];
      }
    }
  });
  const maybeEnding = foundEndings[0];
  const ending = maybeEnding ? `Just ${maybeEnding}` : "Nothing";

  const segments = parseRouteParamsWithStatic(name)
    .flatMap((param) => {
      switch (param.kind) {
        case "static": {
          return [
            `Pages.Internal.RoutePattern.StaticSegment "${camelToKebab(
              param.name
            )}"`,
          ];
        }
        case "dynamic": {
          return [`Pages.Internal.RoutePattern.DynamicSegment "${param.name}"`];
        }
        case "optional": {
          return [];
        }
        case "required-splat": {
          return [];
        }
        case "optional-splat": {
          return [];
        }
      }
    })

    .join(", ");
  return `{ segments = [ ${segments} ], ending = ${ending} }`;
}

/**
 * Convert Strings from camelCase to kebab-case
 * @param {string} input
 * @returns {string}
 */
export function camelToKebab(input) {
  return input.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
}

/**
 * @param {string[]} name
 */
export function paramsRecord(name) {
  return `{ ${parseRouteParams(name).map((param) => {
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
export function routeVariant(name) {
  return `${name.join("__")}`;
}

/**
 * @param {string[]} name
 * @param {string} paramsName
 */
export function destructureRoute(name, paramsName) {
  return emptyRouteParams(name)
    ? `Route.${routeVariant(name)}`
    : `(Route.${routeVariant(name)} ${paramsName})`;
}

export function referenceRouteParams(name, paramsName) {
  return emptyRouteParams(name) ? `{}` : paramsName;
}
/**
 * @param {string[]} name
 */
export function emptyRouteParams(name) {
  return parseRouteParams(name).length === 0;
}

/**
 * @param {string} name
 */
export function toFieldName(name) {
  if (name === "SPLAT") {
    return "splat";
  } else {
    return name.charAt(0).toLowerCase() + name.slice(1);
  }
}
