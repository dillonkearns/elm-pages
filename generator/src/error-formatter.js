"use strict";

import * as kleur from "kleur/colors";

/* Thanks to elm-live for this code! 
   https://github.com/wking-io/elm-live/blob/e317b4914c471addea7243c47f28dcebe27a5d36/lib/src/build.js#L65
 */

/**
 * parseHeader :: (String, String) -> String
 *
 * This function takes in the error title and the path to the file with the error and formats it like elm make's regular output
 **/
/**
 * @param {string} rule
 * @param {string} path
 * */
function parseHeader(rule, path) {
  return kleur.cyan(
    `-- ${(rule || "").replace("-", " ")} --------------- ${path || ""}
`
  );
}

/**
 * This function takes in the error message and makes sure that it has the proper formatting
 *
 * ```elm ish
 * parseMsg :: String | Object -> String
 * ```
 *
 * @param {Message} msg
 * */
function parseMsg(msg) {
  if (typeof msg === "string") {
    return msg;
  } else {
    if (msg.underline && msg.color) {
      return kleur[toKleurColor(msg.color)]().underline();
    } else if (msg.underline) {
      return kleur.underline(msg.string);
    } else if (msg.color) {
      return kleur[toKleurColor(msg.color)](msg.string);
    } else {
      return msg.string;
    }
  }
}

/**
 * @param {string} color
 * @returns {keyof import("kleur").Kleur}
 * */
function toKleurColor(color) {
  if (color.startsWith("#")) {
    const hexCode = color.slice(1);
    switch (hexCode) {
      // color codes from https://github.com/jfmengels/node-elm-review/blob/d4a6de524cfc33c490c751a3bb084e86accf25fd/template/src/Elm/Review/Text.elm#L80
      case "33BBC8": {
        return "cyan";
      }
      case "FFFF00": {
        return "yellow";
      }
      case "008000": {
        return "green";
      }
    }
    return "red";
  } else {
    return color.toLowerCase();
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
export const restoreColor = (error) => {
  try {
    if (error.type === "compile-errors") {
      return error.errors
        .map(({ problems, path }) =>
          problems.map(restoreProblem(path)).join("\n\n\n")
        )
        .join("\n\n\n\n\n");
    } else if (error.type === "review-errors") {
      return error.errors
        .map(({ errors, path }) =>
          errors.map(restoreProblem(path)).join("\n\n\n")
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
 * @param {string|RootObject[]} error
 * @returns {string}
 */
export function restoreColorSafe(error) {
  try {
    if (typeof error === "string") {
      const asJson = JSON.parse(error);
      return restoreColor(asJson);
    } else if (Array.isArray(error)) {
      return error.map(restoreColor).join("\n\n\n");
    } else {
      return restoreColor(error);
    }
  } catch (e) {
    return error;
  }
}

/**
 * parseMsg :: { errors: Array } -> String
 *
 * This function takes in the array of compiler errors and maps over them to generate a formatted compiler error
 **/
const restoreProblem =
  (/** @type {string} */ path) => (/** @type {Problem | IError} */ info) => {
    if (info.rule && info.formatted) {
      return [
        parseHeader(info.rule, path),
        ...info.formatted.map(parseMsg),
      ].join("");
    } else if (typeof info.message === "string") {
      return info.message;
    } else {
      // console.log("info.message", info.message);
      return [
        parseHeader(info.title, path),
        ...info.message.map(parseMsg),
      ].join("");
    }
  };

/** @typedef { CompilerError | ReportError | IElmReviewError } RootObject */

/** @typedef { { type: "compile-errors"; errors: Error_[]; } } CompilerError */
/** @typedef { { type: "error"; path: string; title: string; message: Message[]; } } ReportError */

/** @typedef { { line: number; column: number; } } Location */

/** @typedef { { start: Location; end: Location; } }  Region */

/** @typedef { { title: string; region: Region; message: Message[]; } } Problem */
/** @typedef {string | {underline: boolean; color: string?; string: string}} Message */

/** @typedef { { path: string; name: string; problems: Problem[]; } } Error_  */

/** @typedef  { { type: "review-errors"; errors: IFileError[]; } } IElmReviewError */

/** @typedef  {  { path: string; errors: IError[]; } } IFileError */

/** @typedef  { { rule: string; formatted: unknown[]; ruleLink: string; message: string; details: string[]; region: IRegion; fix?: { range: IRegion; string: string; }[]; } } IError */

/** @typedef  {  { start: IPosition; end: IPosition; } } IRegion */
/** @typedef  {   { line: number; column: number; } } IPosition */
