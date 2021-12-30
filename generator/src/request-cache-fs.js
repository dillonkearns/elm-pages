module.exports = function (/** @type {boolean} */ hasFsAccess) {
  if (hasFsAccess) {
    return {
      fs: require("fs"),
      resetInMemoryFs: () => {},
    };
  } else {
    return {
      fs: require("memfs").fs,
      resetInMemoryFs: require("memfs").vol.reset,
    };
  }
};
