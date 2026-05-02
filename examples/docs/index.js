/** @typedef {{load: (Promise<unknown>); flags: (unknown)}} ElmPagesInit */

/** @type ElmPagesInit */
export default {
  load: async function (elmLoaded) {
    setupImageZoom();
    const app = await elmLoaded;
    // console.log("App loaded", app);
  },
  flags: function () {
    return "You can decode this in Shared.elm using Json.Decode.string!";
  },
};

function setupImageZoom() {
  let dialog;

  function getDialog() {
    if (!dialog) {
      dialog = document.createElement("dialog");
      dialog.className = "image-zoom-dialog";
      const img = document.createElement("img");
      dialog.appendChild(img);
      dialog.addEventListener("click", () => dialog.close());
      document.body.appendChild(dialog);
    }
    return dialog;
  }

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-zoom-src]");
    if (!trigger) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
    if (typeof HTMLDialogElement === "undefined") return;
    event.preventDefault();

    const dlg = getDialog();
    const img = dlg.querySelector("img");
    img.src = trigger.dataset.zoomSrc;
    img.alt = trigger.dataset.zoomAlt || "";
    dlg.showModal();
  });
}
