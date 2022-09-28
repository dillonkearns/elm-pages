module.exports = function (/** @type {boolean} */ hasFsAccess) {
  if (hasFsAccess) {
    return {
      fs: require("fs"),
      resetInMemoryFs: () => {},
    };
  } else {
    const { vol, fs, Volume } = require("memfs");
    vol.fromJSON({});
    //     vol.reset();
    return {
      fs: fs,
      resetInMemoryFs: () => {
        vol.reset();
      },
    };
  }
};
