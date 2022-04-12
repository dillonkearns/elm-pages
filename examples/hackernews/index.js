export default {
  load: function (elmLoaded) {},
  flags: function () {
    return null;
  },
};

customElements.define(
  "news-comment",
  class extends HTMLElement {
    constructor() {
      super();
      this._commentBody = null;
      this.expanded = true;
    }

    get commentBody() {
      return this._commentBody;
    }

    set commentBody(value) {
      if (this._commentBody === value) return;
      this._commentBody = value;
    }

    toggle() {
      this.expanded = !this.expanded;
      this.connectedCallback();
    }

    connectedCallback() {
      this.shadow = this.shadow || this.attachShadow({ mode: "open" });
      const div = document.createElement("div");
      let toggleClass = this.expanded ? "open" : "closed";
      let displayStyle = this.expanded ? "block" : "none";
      div.classList = `toggle ${toggleClass}`;
      const button = document.createElement("a");
      button.textContent = this.expanded ? "[-]" : "[+] comments collapsed";
      button.addEventListener("click", () => this.toggle());
      div.appendChild(button);
      const nestedComments =
        (this._commentBody && this._commentBody.comments) || [];
      const nested = document.createElement("ul");
      nested.style["display"] = displayStyle;
      nestedComments.forEach((comment) => {
        const newElement = document.createElement("news-comment");
        newElement.commentBody = comment;
        nested.appendChild(newElement);
      });

      this.shadow.innerHTML = `<ul
        class="comment-children"
        style="display: ${displayStyle}"
      >
        <div class="text">${
          (this._commentBody && this._commentBody.content) || ""
        }</div>
      </ul>`;
      this.shadow.appendChild(nested);
      this.shadow.prepend(div);
    }
  }
);
