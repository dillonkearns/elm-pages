// @ts-ignore
import { Elm } from "../ManifestMain.elm";
// @ts-ignore
const fs = require("fs");

const app = Elm.ManifestMain.init({ flags: null });
app.ports.generateManifest.subscribe((manifestJson: Object) => {
  fs.writeFileSync("./dist/manifest.webmanifest", JSON.stringify(manifestJson));
});
