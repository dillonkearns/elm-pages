/** @typedef {{load: (Promise<unknown>); flags: (unknown)}} ElmPagesInit */

/** @type ElmPagesInit */
export default {
  load: function (elmLoaded) {
    document.addEventListener("DOMContentLoaded", function (event) {});
  },
  flags: function () {
    return "Hello from flags!";
  },
};
