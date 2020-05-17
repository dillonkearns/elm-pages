const path = require("path");
const dir = "content/";
const glob = require("glob");
const fs = require("fs");
const sharp = require("sharp");
const parseFrontmatter = require("./frontmatter.js");

// Because we use node-glob, we must use `/` as a separator on all platforms. See https://github.com/isaacs/node-glob#windows
const PATH_SEPARATOR = '/';

module.exports = async function wrapper() {
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

    const foundMetadata = parseFrontmatter(
      fullPath,
      fs.readFileSync(fullPath).toString()
    );

    const metadata = {
      path: relative,
      metadata: JSON.stringify(foundMetadata.data),
      document: true
    };
    return metadata;
  };
}

function relativeImagePath(imageFilepath) {
  var pathFragments = imageFilepath;
  //remove extesion and split into fragments
  const fragmentsWithExtension = pathFragments.split(PATH_SEPARATOR);
  fragmentsWithExtension.splice(0, 1);
  pathFragments = pathFragments.replace(/\.[^/.]+$/, "").split(PATH_SEPARATOR);
  pathFragments.splice(0, 1);
  const fullPath = imageFilepath;
  var relative = imageFilepath.slice(dir.length - 1);
  return { path: relative, pathFragments, fragmentsWithExtension };
}

async function generate(scanned) {
  // Generate Pages/My/elm
  // Documents ->
  //     Routes
  //     All routes
  //     URL parser/encoder
  //     route -> metadata
  // Assets ->
  //     Record

  var routeRecord = {};
  var allRoutes = [];
  var routeToMetadata = [];
  var routeToExt = [];
  var routeToSource = [];

  for (var i = 0; i < scanned.length; i++) {
    var pathFragments = scanned[i].path;
    //remove extesion and split into fragments
    pathFragments = pathFragments.replace(/\.[^/.]+$/, "").split(PATH_SEPARATOR);
    const is404 = pathFragments.length == 1 && pathFragments[0] == "404";
    const ext = path.extname(scanned[i].path);

    // const elmType = pathFragments.map(toPascalCase).join("");
    const elmType =
      "(buildPage [ " +
      pathFragments
        .filter(fragment => fragment !== "index")
        .map(fragment => `"${fragment}"`)
        .join(", ") +
      " ])";
    if (!is404) {
      captureRouteRecord(pathFragments, elmType, routeRecord);
      allRoutes.push(elmType);
      // routeToMetadata.push(formatCaseInstance(elmType, scanned[i].metadata));
      // routeToExt.push(formatCaseInstance(elmType, ext));
      // routeToSource.push(formatCaseInstance(elmType, scanned[i].path));
    }
  }
  return {
    // routes: toFlatRouteType(allRoutes),
    allRoutes: formatAsElmList("allPages", allRoutes),
    routeRecord: toElmRecord("pages", routeRecord, true),
    // routeToMetadata: formatCaseStatement("toMetadata", routeToMetadata),
    // routeToDocExtension: formatCaseStatement("toExt", routeToExt),
    // routeToSource: formatCaseStatement("toSourcePath", routeToSource),
    imageAssetsRecord: toElmRecord("images", await getImageAssets(), true),
    allImages: await allImageAssetNames()
  };
}
function listImageAssets() {
  return glob
    .sync("images/**/*", {})
    .filter(filePath => !fs.lstatSync(filePath).isDirectory())
    .map(relativeImagePath);
}
async function getImageAssets() {
  var assetsRecord = {};
  await Promise.all(listImageAssets().map(async info => {
    captureRouteRecord(info.pathFragments, await elmType(info), assetsRecord);
  }));

  return assetsRecord;
}
function allImageAssetNames() {
  return Promise.all(listImageAssets().map(async info => {
    return elmType(info);
  }));
}
async function elmType(info) {
  const pathFragments = info.fragmentsWithExtension
    .map(fragment => `"${fragment}"`)
    .join(", ");
  const metadata = await sharp(`images/${info.path}`).metadata();
  return `(buildImage [ ${pathFragments} ] { width = ${metadata.width}, height = ${metadata.height} })`
}
function toPascalCase(str) {
  var pascal = str.replace(/(\-\w)/g, function (m) {
    return m[1].toUpperCase();
  });
  return pascal.charAt(0).toUpperCase() + pascal.slice(1);
}

function toCamelCase(str) {
  var pascal = str.replace(/(\-\w)/g, function (m) {
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
  return name + " =\n" + formatRecord([], routeRecord, asType, 1);
}

function formatRecord(directoryPath, rec, asType, level) {
  var keyVals = [];
  const indentation = " ".repeat(level * 4);
  var valsAtThisLevel = [];
  const keys = Object.keys(rec);
  for (const key of keys) {
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
      keyVals.push(
        key +
        " =\n" +
        formatRecord(directoryPath.concat(key), val, asType, level + 1)
      );
    }
  }
  keyVals.push(
    `directory = ${
    keys.includes("index") ? "directoryWithIndex" : "directoryWithoutIndex"
    } [${directoryPath.map(pathFragment => `"${pathFragment}"`).join(", ")}]`
  );
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

  var signature = name + " : List (PagePath PathKey)\n";

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

function formatAsElmUrlToString(pieces) {
  var toString = pieces.map(p => p.toString).join("\n\n");

  return `routeToString : Route -> String
routeToString route =
    case route of
${toString} `;
}
