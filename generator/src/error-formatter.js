const kleur = require("kleur");

/* Thanks to elm-live for this code! 
   https://github.com/wking-io/elm-live/blob/e317b4914c471addea7243c47f28dcebe27a5d36/lib/src/build.js#L65
 */

/**
 * parseHeader :: (String, String) -> String
 *
 * This function takes in the error title and the path to the file with the error and formats it like elm make's regular output
 **/
/**
 * @param {string} title
 * @param {string} path
 * */
const parseHeader = (title, path) =>
  kleur.cyan(
    `-- ${title.replace("-", " ")} --------------- ${path || ""}
`
  );

/**
 * parseMsg :: String|Object -> String
 *
 * This function takes in the error message and makes sure that it has the proper formatting
 **/
/**
 * @param {Message} msg
 * */
function parseMsg(msg) {
  if (typeof msg === "string") {
    return msg;
  } else {
    if (msg.underline && msg.color) {
      return kleur[msg.color.toLowerCase()]().underline(msg.string);
    } else if (msg.underline) {
      return kleur.underline(msg.string);
    } else if (msg.color) {
      return kleur[msg.color.toLowerCase()](msg.string);
    } else {
      return msg.string;
    }
  }
}

/** @typedef {{problems: {title: string; message: unknown}[]; path: string}[]} Errors } */

/**
 * parseMsg :: { errors: Array } -> String
 *
 * This function takes in the array of compiler errors and maps over them to generate a formatted compiler error
 **/
/**
 * @param {RootObject} error
 * */
const restoreColor = (error) => {
  try {
    if (error.type === "compile-errors") {
      return error.errors
        .map(({ problems, path }) =>
          problems.map(restoreProblem(path)).join("\n\n\n")
        )
        .join("\n\n\n\n\n");
    } else if (error.type === "error") {
      return restoreProblem(error.path)(error);
    } else {
      throw `Unexpected error ${JSON.stringify(error, null, 2)}`;
    }
  } catch (e) {
    console.trace("Unexpected error format", e.toString());
    return error.toString();
  }
};

/**
 * parseMsg :: { errors: Array } -> String
 *
 * This function takes in the array of compiler errors and maps over them to generate a formatted compiler error
 **/
const restoreProblem =
  (/** @type {string} */ path) =>
  (/** @type {{title:string; message: Message[]}} */ { title, message }) =>
    [parseHeader(title, path), ...message.map(parseMsg)].join("");

module.exports = { restoreColor };

/** @typedef { CompilerError | ReportError } RootObject */

/** @typedef { { type: "compile-errors"; errors: Error_[]; } } CompilerError */
/** @typedef { { type: "error"; path: string; title: string; message: Message[]; } } ReportError */

/** @typedef { { line: number; column: number; } } Location */

/** @typedef { { start: Location; end: Location; } }  Region */

/** @typedef { { title: string; region: Region; message: Message[]; } } Problem */
/** @typedef {string | {underline: boolean; color: string?; string: string}} Message */

/** @typedef { { path: string; name: string; problems: Problem[]; } } Error_  */
