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
      this.draw();
    }

    connectedCallback() {
      this.shadow = this.shadow || this.attachShadow({ mode: "closed" });
      this.draw();
    }

    draw() {
      this.shadow.innerHTML = "";
      const nestedComments =
        (this._commentBody && this._commentBody.comments) || [];
      const div = document.createElement("div");
      let toggleClass = this.expanded ? "open" : "closed";
      let displayStyle = this.expanded ? "block" : "none";
      div.classList = `toggle ${toggleClass}`;
      const button = document.createElement("a");
      button.textContent = this.expanded ? "[-]" : "[+] comments collapsed";
      button.addEventListener("click", () => this.toggle());
      if (nestedComments.length > 0) {
        div.appendChild(button);
      }
      const nested = document.createElement("ul");
      nested.style["display"] = displayStyle;
      nestedComments.forEach((comment) => {
        const newElement = document.createElement("news-comment");
        newElement.commentBody = comment;
        nested.appendChild(newElement);
      });

      let style = document.createElement("style");

      style.textContent = `.item-view-comments {
  background-color: #fff;
  margin-top: 10px;
  padding: 0 2em 0.5em;
}

body {
  color: red !important;
}

.item-view-comments-header {
  margin: 0;
  font-size: 1.1em;
  padding: 1em 0;
  position: relative;
}

.item-view-comments-header .spinner {
  display: inline-block;
  margin: -15px 0;
}

.comment-children {
  list-style-type: none;
  padding: 0;
  margin: 0;
}

@media (max-width: 600px) {
  .item-view-header h1 {
    font-size: 1.25em;
  }
}

.comment-children .comment-children {
  margin-left: 1.5em;
}

.comment {
  border-top: 1px solid #eee;
  position: relative;
}

.comment .by,
.comment .text,
.comment .toggle {
  font-size: 0.9em;
  margin: 1em 0;
}

.comment .by {
  color: #626262;
}

.comment .by a {
  color: #626262;
  text-decoration: underline;
}

.comment .text {
  overflow-wrap: break-word;
}

.comment .text a:hover {
  color: #5f3392;
}

.comment .text pre {
  white-space: pre-wrap;
}

.comment .toggle {
  background-color: #fffbf2;
  padding: 0.3em 0.5em;
  border-radius: 4px;
}

.comment .toggle a {
  color: #626262;
  cursor: pointer;
}

.comment .toggle.open {
  padding: 0;
  background-color: transparent;
  margin-bottom: -0.5em;
}
`;

      const commentLi = document.createElement("li");
      commentLi.classList = "comment";
      // this.shadow.innerHTML =
      commentLi.innerHTML = `
<div class="text">${
        (this._commentBody && this._commentBody.content) || ""
      }</div>
<ul
class="comment-children"
style="display: ${displayStyle}"
>
</ul>
      `;
      commentLi.appendChild(div);
      this.shadow.append(commentLi);
      this.shadow.appendChild(nested);
      this.shadow.prepend(style);
    }
  }
);
