import * as fs from "fs";
import * as fsExtra from "fs-extra";
import * as path from "path";
import * as kleur from "kleur/colors";
import { fileURLToPath } from "url";
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * @param {string} name
 */
export async function run(name) {
  console.log("Creating " + name + " project...");

  const appRoot = path.resolve(name.toString());
  const template = path.join(__dirname, "../template");

  if (!fs.existsSync(name)) {
    try {
      fsExtra.copySync(template, appRoot);
      fs.renameSync(
        path.resolve(appRoot, "gitignore"),
        path.resolve(appRoot, ".gitignore")
      );
      /* Since .elm-pages is in source-directories, make sure we create it before running any elm-pages commands
       in case we run any install commands first.  See: https://github.com/dillonkearns/elm-pages/issues/205
       */
      fs.mkdirSync(path.join(appRoot, ".elm-pages"), { recursive: true });
    } catch (err) {
      console.log(err);
      process.exit(1);
    }
  } else {
    console.log("The directory " + name + " already exists. Aborting.");
    process.exit(1);
  }

  console.log(
    kleur.green("Project is successfully created in `" + appRoot + "`.")
  );
}
