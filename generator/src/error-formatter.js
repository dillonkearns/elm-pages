const kleur = require("kleur");

/* Thanks to elm-live for this code! 
   https://github.com/wking-io/elm-live/blob/e317b4914c471addea7243c47f28dcebe27a5d36/lib/src/build.js#L65
 */

/**
 * parseHeader :: (String, String) -> String
 *
 * This function takes in the error title and the path to the file with the error and formats it like elm make's regular output
 **/
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
function parseMsg(msg) {
  if (typeof msg === "string") {
    return msg;
  } else {
    if (msg.underline) {
      return kleur.underline(msg.string);
    } else if (msg.color) {
      return kleur[msg.color.toLowerCase()](msg.string);
    } else {
      return msg.string;
    }
  }
}

/**
 * parseMsg :: { errors: Array } -> String
 *
 * This function takes in the array of compiler errors and maps over them to generate a formatted compiler error
 **/
const restoreColor = (errors) => {
  try {
    return errors
      .map(({ problems, path }) =>
        problems.map(restoreProblem(path)).join("\n\n\n")
      )
      .join("\n\n\n\n\n");
  } catch (error) {
    return error.toString();
  }
};

/**
 * parseMsg :: { errors: Array } -> String
 *
 * This function takes in the array of compiler errors and maps over them to generate a formatted compiler error
 **/
const restoreProblem = (path) => ({ title, message }) =>
  [parseHeader(title, path), ...message.map(parseMsg)].join("");

module.exports = { restoreColor };
