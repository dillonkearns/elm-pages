/**
 * Patches the compiled server-side Elm code (the "CLI app") so it can run
 * under Node.
 *
 * This is the only place these patches are made. `elm-pages build`, the dev
 * server, `elm-pages run` and the other commands that compile the CLI app all
 * call this function, so they cannot drift apart
 * (https://github.com/dillonkearns/elm-pages/issues/622).
 *
 * @param {string} elmCode the JavaScript that `lamdera make` wrote
 * @returns {string}
 */
export function patchCompiledCliApp(elmCode) {
  return (
    elmCode
      // `asJsonView` in `HtmlPrinter.elm` returns a placeholder string. Swap
      // it for code that hands the virtual DOM to Elm as JSON.
      .replace(
        /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
        `return ${forceThunksSource}
  return _Json_wrap(forceThunks(html));
`
      )
      .replace(/console\.log..App dying../, "")
  );
}

/**
 * `HtmlPrinter.elm` cannot print a lazy node (`Html.Lazy`) until it has been
 * built, so `forceThunks` walks the virtual DOM and builds every lazy node
 * before the HTML is turned into JSON.
 *
 * The text starts by ending the statement it is spliced into (`return ...`)
 * and ends inside a new function, so the rest of the original function body
 * still parses.
 *
 * Source: https://github.com/elm-explorations/test/blob/d5eb84809de0f8bbf50303efd26889092c800609/src/Elm/Kernel/HtmlAsJson.js
 */
const forceThunksSource = ` _HtmlAsJson_toJson(x)
}

              var virtualDomKernelConstants =
  {
    nodeTypeTagger: 4,
    nodeTypeThunk: 5,
    kids: "e",
    refs: "l",
    thunk: "m",
    node: "k",
    value: "a"
  }

function forceThunks(vNode) {
if ( (typeof vNode !== "undefined" && vNode.$ === "#2") // normal/debug mode
     || (typeof vNode !== "undefined" && typeof vNode.$ === "undefined" && typeof vNode.a == "string" && typeof vNode.b == "object" ) // optimize mode
   ) {
    // This is a tuple (the kids : List (String, Html) field of a Keyed node); recurse into the right side of the tuple
    vNode.b = forceThunks(vNode.b);
  }
  if (typeof vNode !== 'undefined' && vNode.$ === virtualDomKernelConstants.nodeTypeThunk && !vNode[virtualDomKernelConstants.node]) {
    // This is a lazy node; evaluate it
    var args = vNode[virtualDomKernelConstants.thunk];
    vNode[virtualDomKernelConstants.node] = vNode[virtualDomKernelConstants.thunk].apply(args);
    // And then recurse into the evaluated node
    vNode[virtualDomKernelConstants.node] = forceThunks(vNode[virtualDomKernelConstants.node]);
  }
  if (typeof vNode !== 'undefined' && vNode.$ === virtualDomKernelConstants.nodeTypeTagger) {
    // This is an Html.map; recurse into the node it is wrapping
    vNode[virtualDomKernelConstants.node] = forceThunks(vNode[virtualDomKernelConstants.node]);
  }
  if (typeof vNode !== 'undefined' && typeof vNode[virtualDomKernelConstants.kids] !== 'undefined') {
    // This is something with children (either a node with kids : List Html, or keyed with kids : List (String, Html));
    // recurse into the children
    vNode[virtualDomKernelConstants.kids] = vNode[virtualDomKernelConstants.kids].map(forceThunks);
  }
  return vNode;
}

function _HtmlAsJson_toJson(html) {
`;
