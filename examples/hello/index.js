"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const config = {
    load: async function (elmLoaded) {
        const app = await elmLoaded;
        console.log("App loaded", app);
    },
    flags: function () {
        return "You can decode this in Shared.elm using Json.Decode.string!";
    },
};
exports.default = config;
