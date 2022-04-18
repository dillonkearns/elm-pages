const fsStub = {
  promises: {
    access: function () {
      throw "";
    },
  },
};

module.exports = function (/** @type {boolean} */ hasFsAccess) {
  return {
    fs: fsStub,
    resetInMemoryFs: () => {},
  };
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
