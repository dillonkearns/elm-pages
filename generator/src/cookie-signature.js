// Source: https://github.com/tj/node-cookie-signature/blob/7deca8b38110a3bd65841c34359794706cc7c60f/index.js
// From this NPM package: https://www.npmjs.com/package/cookie-signature
// Couldn't use it directly because it imports crypto, but it needs to be injected instead so it's compatible with other runtimes like Cloudflare or Deno

module.exports = {
  sign: function (crypto, val, secret) {
    if ("string" != typeof val)
      throw new TypeError("Cookie value must be provided as a string.");
    if (null == secret) throw new TypeError("Secret key must be provided.");
    return (
      val +
      "." +
      crypto
        .createHmac("sha256", secret)
        .update(val)
        .digest("base64")
        .replace(/\=+$/, "")
    );
  },

  /**
   * Unsign and decode the given `input` with `secret`,
   * returning `false` if the signature is invalid.
   *
   * @param {String} input
   * @param {String} secret
   * @return {String|Boolean}
   * @api private
   */

  unsign: function (crypto, input, secret) {
    if ("string" != typeof input)
      throw new TypeError("Signed cookie string must be provided.");
    if (null == secret) throw new TypeError("Secret key must be provided.");
    var tentativeValue = input.slice(0, input.lastIndexOf(".")),
      expectedInput = exports.sign(tentativeValue, secret),
      expectedBuffer = Buffer.from(expectedInput),
      inputBuffer = Buffer.from(input);
    return expectedBuffer.length === inputBuffer.length &&
      crypto.timingSafeEqual(expectedBuffer, inputBuffer)
      ? tentativeValue
      : false;
  },
};
