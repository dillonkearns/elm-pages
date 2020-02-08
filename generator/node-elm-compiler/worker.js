var temp = require("temp").track();
var path = require("path");
var jsEmitterFilename = "emitter.js";

var KNOWN_MODULES =
  [
    "fullscreen",
    "embed",
    "worker",
    "Basics",
    "Maybe",
    "List",
    "Array",
    "Char",
    "Color",
    "Transform2D",
    "Text",
    "Graphics",
    "Debug",
    "Result",
    "Task",
    "Signal",
    "String",
    "Dict",
    "Json",
    "Regex",
    "VirtualDom",
    "Html",
    "Css"
  ];


// elmModuleName is optional, and is by default inferred based on the filename.
module.exports = function (compile) {
  return function (projectRootDir, modulePath, moduleName, workerArgs) {
    var originalWorkingDir = process.cwd();
    process.chdir(projectRootDir);

    return createTmpDir()
      .then(function (tmpDirPath) {
        var dest = path.join(tmpDirPath, jsEmitterFilename);

        return compileEmitter(compile, modulePath, { output: dest })
          .then(function () { return runWorker(dest, moduleName, workerArgs) });
      })
      .then(function (worker) {
        process.chdir(originalWorkingDir);
        return worker;
      })
      .catch(function (err) {
        process.chdir(originalWorkingDir);
        throw Error(err);
      });
  };
};

function createTmpDir() {
  return new Promise(function (resolve, reject) {
    temp.mkdir("node-elm-compiler", function (err, tmpDirPath) {
      if (err) {
        reject(err);
      } else {
        resolve(tmpDirPath);
      }
    });
  });
}

function suggestModulesNames(Elm) {
  return Object.keys(Elm).filter(function (key) {
    return KNOWN_MODULES.indexOf(key) === -1;
  })
}

function missingEntryModuleMessage(moduleName, Elm) {
  var errorMessage = "I couldn't find the entry module " + moduleName + ".\n";
  var suggestions = suggestModulesNames(Elm);

  if (suggestions.length > 1) {
    errorMessage += "\nMaybe you meant one of these: " + suggestions.join(",");
  } else if (suggestions.length === 1) {
    errorMessage += "\nMaybe you meant: " + suggestions;
  }

  errorMessage += "\nYou can pass me a different module to use with --module=<moduleName>";

  return errorMessage;
}

function noPortsMessage(moduleName) {
  var errorMessage = "The module " + moduleName + " doesn't expose any ports!\n";

  errorMessage += "\n\nTry adding something like";
  errorMessage += "port foo : Value\nport foo =\n    someValue\n\nto " + moduleName + "!";

  return errorMessage.trim();
}

function runWorker(jsFilename, moduleName, workerArgs) {
  return new Promise(function (resolve, reject) {
    var Elm = require(jsFilename).Elm;

    if (!(moduleName in Elm)) {
      return reject(missingEntryModuleMessage(moduleName, Elm));
    }

    var worker = Elm[moduleName].init(workerArgs);

    if (Object.keys(worker.ports).length === 0) {
      return reject(noPortsMessage(moduleName));
    }

    return resolve(worker);
  });
}

function compileEmitter(compile, src, options) {
  return new Promise(function (resolve, reject) {
    compile(src, options)
      .on("close", function (exitCode) {
        if (exitCode === 0) {
          resolve(exitCode);
        } else {
          reject("Errored with exit code " + exitCode);
        }
      })
  });
}
