import Prism from "prismjs";
import "prismjs/components/prism-elm";
import "./native-shim.js";

customElements.define(
  "code-editor",
  class extends HTMLElement {
    constructor() {
      super();
      this._editorValue =
        "-- If you see this, the Elm code didn't set the value.";
    }

    get editorValue() {
      return this._editorValue;
    }

    set editorValue(value) {
      if (this._editorValue === value) return;
      this._editorValue = value;
      if (!this._editor) return;
      this._editor.setValue(value);
    }

    connectedCallback() {
      let shadow = this.attachShadow({ mode: "open" });

      let style = document.createElement("style");
      style.textContent = `
        @import "https://cdnjs.cloudflare.com/ajax/libs/prism/1.17.1/themes/prism-okaidia.min.css";

        pre {
          padding: 20px;
          background: black;
          overflow: scroll;
        }
      `;

      let code = document.createElement("code");
      code.setAttribute("class", "language-elm");
      code.innerHTML = Prism.highlight(this.editorValue, Prism.languages.elm, "elm");

      let pre = document.createElement("pre");
      pre.appendChild(code);

      shadow.appendChild(style);
      shadow.appendChild(pre);
    }
  }
);
