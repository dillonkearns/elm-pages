// Helpers for the tests that check what the app does when it starts.
// Pass them to `cy.visit(url, { onBeforeLoad })`.

/**
 * Record every value that `document.title` is set to, in `win.titlesSet`.
 *
 * This wraps the setter instead of watching the DOM, so that a title that is
 * set and then corrected right away is still recorded.
 */
export function recordTitles(win) {
  const original = Object.getOwnPropertyDescriptor(
    win.Document.prototype,
    "title"
  );
  win.titlesSet = [];
  Object.defineProperty(win.document, "title", {
    configurable: true,
    get() {
      return original.get.call(this);
    },
    set(value) {
      win.titlesSet.push(value);
      original.set.call(this, value);
    },
  });
}

/**
 * Hold back `requestAnimationFrame` callbacks, like a browser does for a tab
 * that is in the background. Elm draws its first view right away, and every
 * later view in an animation frame, so with this only the first view is drawn.
 *
 * Call `win.runHeldAnimationFrames()` to let the held callbacks run and stop
 * holding new ones back.
 */
export function holdAnimationFrames(win) {
  const realRequestAnimationFrame = win.requestAnimationFrame.bind(win);
  const held = [];
  let holding = true;
  // Elm keeps a reference to this function when it loads, so it has to keep
  // working after the frames are let go.
  win.requestAnimationFrame = (callback) => {
    if (holding) {
      held.push(callback);
      return 0;
    }
    return realRequestAnimationFrame(callback);
  };
  win.runHeldAnimationFrames = () => {
    holding = false;
    held.splice(0).forEach((callback) => realRequestAnimationFrame(callback));
  };
}

/**
 * Record every element that is removed from the page, in
 * `win.removedElements` (as HTML strings).
 */
export function recordRemovedElements(win) {
  win.removedElements = [];
  new win.MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.removedNodes) {
        if (node.nodeType === 1) {
          win.removedElements.push(node.outerHTML.slice(0, 200));
        }
      }
    }
  }).observe(win.document, { childList: true, subtree: true });
}

/**
 * Remember the elements that the server sent, before the app starts:
 * `win.serverElements` is every element in the body that the app manages.
 */
export function rememberServerElements(win) {
  // This listener is added before the one that starts the app, so it runs first.
  win.document.addEventListener("DOMContentLoaded", () => {
    win.serverElements = Array.from(
      win.document.body.querySelectorAll("*")
    ).filter((element) => !element.closest("script, style"));
  });
}
