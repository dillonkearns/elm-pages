import { Elm } from "./Main.elm";
import * as ElmDebugger from "elm-debug-transformer";

if (process.env.NODE_ENV === "development") {
  // Only runs in development and will be stripped from production build.
  // See https://parceljs.org/production.html
  ElmDebugger.register();
}
Elm.Main.init({});
