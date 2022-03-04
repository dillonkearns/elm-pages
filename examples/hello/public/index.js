/** @typedef {{load: (Promise<unknown>); flags: (unknown)}} ElmPagesInit */

/** @type ElmPagesInit */
export default {
  load: async function (elmLoaded) {
    const app = await elmLoaded;
    console.log("App loaded", app);
  },
  flags: function () {
    return "You can decode this in Shared.elm using Json.Decode.string!";
  },
};
