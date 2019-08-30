import Prism from "prismjs";
import "prismjs/components/prism-elm";

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
      shadow.innerHTML = `
      <style>@import "https://cdnjs.cloudflare.com/ajax/libs/prism/1.17.1/themes/prism-okaidia.min.css";</style>

      <pre class="line-numbers" style="padding: 20px; background: black;">
        <code class="language-elm">
${Prism.highlight(this._editorValue, Prism.languages.elm, "elm")}
        </code>
      </pre>
      `;
    }
  }
);
