const path = require("path");
const matter = require("gray-matter");
const dir = "content/";
const glob = require("glob");
const fs = require("fs");

module.exports = function wrapper() {
  return generate(scan());
};

function scan() {
  // scan content directory for documents
  const content = glob
    .sync(dir + "**/*", {})
    .filter(filePath => !fs.lstatSync(filePath).isDirectory())
    .map(unpackFile());
  return content;
}

function unpackFile() {
  return filepath => {
    const fullPath = filepath;
    var relative = filepath.slice(dir.length);
    const foundMetadata = matter(fs.readFileSync(fullPath).toString());

    const metadata = {
      path: relative,
      metadata: JSON.stringify(foundMetadata.data),
      document: true
    };
    return metadata;
  };
}

function generate(scanned) {
  // Generate Pages/My/elm
  // Documents ->
  //     Routes
  //     All routes
  //     URL parser/encoder
  //     route -> metadata
  // Assets ->
  //     Record

  var routeRecord = {};
  var assetsRecord = {};
  var allRoutes = [];
  var urlParser = [];
  var routeToMetadata = [];
  var routeToExt = [];
  var routeToSource = [];
  for (var i = 0; i < scanned.length; i++) {
    var pathFragments = scanned[i].path;
    //remove extesion and split into fragments
    pathFragments = pathFragments.replace(/\.[^/.]+$/, "").split(path.sep);
    const is404 = pathFragments.length == 1 && pathFragments[0] == "404";
    const ext = path.extname(scanned[i].path);
    if (scanned[i].document) {
      // const elmType = pathFragments.map(toPascalCase).join("");
      const elmType =
        "(PageRoute [ " +
        pathFragments
          .filter(fragment => fragment !== "index")
          .map(fragment => `"${fragment}"`)
          .join(", ") +
        " ])";
      if (!is404) {
        captureRouteRecord(pathFragments, elmType, routeRecord);
        allRoutes.push(elmType);
        urlParser.push(formatUrlParser(elmType, pathFragments));
        // routeToMetadata.push(formatCaseInstance(elmType, scanned[i].metadata));
        // routeToExt.push(formatCaseInstance(elmType, ext));
        // routeToSource.push(formatCaseInstance(elmType, scanned[i].path));
      }
    } else {
      captureRouteRecord(pathFragments, scanned[i].path, assetsRecord);
    }
  }
  return {
    exposing: "(simple, Route, all, pages, urlParser, routeToString, assets)",
    // routes: toFlatRouteType(allRoutes),
    allRoutes: formatAsElmList("all", allRoutes),
    routeRecord: toElmRecord("pages", routeRecord, true),
    urlParser: formatAsElmUrlParser(urlParser),
    // urlToString: formatAsElmUrlToString(urlParser),
    // routeToMetadata: formatCaseStatement("toMetadata", routeToMetadata),
    // routeToDocExtension: formatCaseStatement("toExt", routeToExt),
    // routeToSource: formatCaseStatement("toSourcePath", routeToSource),
    assetsRecord: toElmRecord("assets", assetsRecord, false)
  };
}
function toPascalCase(str) {
  var pascal = str.replace(/(\-\w)/g, function(m) {
    return m[1].toUpperCase();
  });
  return pascal.charAt(0).toUpperCase() + pascal.slice(1);
}

function toCamelCase(str) {
  var pascal = str.replace(/(\-\w)/g, function(m) {
    return m[1].toUpperCase();
  });
  return pascal.charAt(0).toLowerCase() + pascal.slice(1);
}

function toFlatRouteType(routes) {
  return `type Route
    = ${routes.join("\n    | ")}
`;
}

function toElmRecord(name, routeRecord, asType) {
  return name + " =\n" + formatRecord(routeRecord, asType, 1);
}

function formatRecord(rec, asType, level) {
  var keyVals = [];
  const indentation = " ".repeat(level * 4);
  var valsAtThisLevel = [];
  for (const key of Object.keys(rec)) {
    var val = rec[key];

    if (typeof val === "string") {
      if (asType) {
        keyVals.push(key + " = " + val);
        valsAtThisLevel.push(val);
      } else {
        keyVals.push(key + ' = "' + val + '"');
        valsAtThisLevel.push('"' + val + '"');
      }
    } else {
      keyVals.push(key + " =\n" + formatRecord(val, asType, level + 1));
    }
  }
  keyVals.push(`all = [ ${valsAtThisLevel.join(", ")} ]`);
  const indentationDelimiter = `\n${indentation}, `;
  return `${indentation}{ ${keyVals.join(indentationDelimiter)}
${indentation}}`;
}

function captureRouteRecord(pieces, elmType, record) {
  var obj = record;
  for (i in pieces) {
    name = toCamelCase(pieces[i]);
    if (parseInt(i) + 1 == pieces.length) {
      obj[name] = elmType;
    } else {
      if (name in obj) {
        obj = obj[name];
      } else {
        obj[name] = {};
        obj = obj[name];
      }
    }
  }
}

function formatAsElmList(name, items) {
  var formatted = items.join("\n    , ");

  var signature = name + " : List PageRoute\n";

  return signature + name + " =\n    [ " + formatted + "\n    ]";
}

function literalUrl(piece) {
  return `s "${piece}"`;
}

function quote(str) {
  return `"${str}"`;
}

function formatCaseInstance(elmType, metadata) {
  return `        ${elmType} ->
            """${metadata}"""`;
}

function formatCaseStatement(name, branches) {
  return `${name} : Route -> String
${name} route =
    case route of
${branches.join("\n\n")}`;
}

function formatUrlParser(elmType, filepathPieces) {
  const urlParser = filepathPieces.map(literalUrl).join(" </> ");

  const urlStringList = filepathPieces.map(quote).join(", ");

  return {
    toString: `        ${elmType} ->\n            Url.Builder.absolute [ ${urlStringList} ] []`,
    parser: `Url.map ${elmType} (${urlParser})`
  };
}

function formatAsElmUrlToString(pieces) {
  var toString = pieces.map(p => p.toString).join("\n\n");

  return `routeToString : Route -> String
routeToString route =
    case route of
${toString} `;
}

function formatAsElmUrlParser(pieces) {
  var parser =
    "    [ " + pieces.map(p => p.parser).join("\n        , ") + "\n        ]";

  return `urlParser : Url.Parser (PageRoute -> a) a
urlParser =\n    Url.oneOf\n    ${parser} `;
}
