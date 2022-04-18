const p=function(){const o=document.createElement("link").relList;if(o&&o.supports&&o.supports("modulepreload"))return;for(const t of document.querySelectorAll('link[rel="modulepreload"]'))s(t);new MutationObserver(t=>{for(const n of t)if(n.type==="childList")for(const r of n.addedNodes)r.tagName==="LINK"&&r.rel==="modulepreload"&&s(r)}).observe(document,{childList:!0,subtree:!0});function i(t){const n={};return t.integrity&&(n.integrity=t.integrity),t.referrerpolicy&&(n.referrerPolicy=t.referrerpolicy),t.crossorigin==="use-credentials"?n.credentials="include":t.crossorigin==="anonymous"?n.credentials="omit":n.credentials="same-origin",n}function s(t){if(t.ep)return;t.ep=!0;const n=i(t);fetch(t.href,n)}};p();var h={load:function(e){},flags:function(){return null}};customElements.define("news-comment",class extends HTMLElement{constructor(){super();this._commentBody=null,this.expanded=!0}get commentBody(){return this._commentBody}set commentBody(e){this._commentBody!==e&&(this._commentBody=e)}toggle(){this.expanded=!this.expanded,this.draw()}connectedCallback(){this.shadow=this.shadow||this.attachShadow({mode:"closed"}),this.draw()}draw(){this.shadow.innerHTML="";const e=this._commentBody&&this._commentBody.comments||[],o=document.createElement("div");let i=this.expanded?"open":"closed",s=this.expanded?"block":"none";o.classList=`toggle ${i}`;const t=document.createElement("a");t.textContent=this.expanded?"[-]":"[+] comments collapsed",t.addEventListener("click",()=>this.toggle()),e.length>0&&o.appendChild(t);const n=document.createElement("ul");n.style.display=s,e.forEach(l=>{const d=document.createElement("news-comment");d.commentBody=l,n.appendChild(d)});let r=document.createElement("style");r.textContent=`.item-view-comments {
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
`;const c=document.createElement("li");c.classList="comment",c.innerHTML=`
<div class="text">${this._commentBody&&this._commentBody.content||""}</div>
<ul
class="comment-children"
style="display: ${s}"
>
</ul>
      `,c.appendChild(o),this.shadow.append(c),this.shadow.appendChild(n),this.shadow.prepend(r)}});let m,a;function u(){let e=window.location.pathname.replace(/(\w)$/,"$1/");e.endsWith("/")||(e=e+"/");const o=Elm.Main.init({flags:{secrets:null,isPrerendering:!1,isDevServer:!1,isElmDebugMode:!1,contentJson:{},pageDataBase64:document.getElementById("__ELM_PAGES_BYTES_DATA__").innerHTML,userFlags:h.flags()}});return o.ports.toJsPort.subscribe(i=>{f()}),o}function f(){if(a!==""){const e=document.querySelector(`[name=${a}]`);e&&e.scrollIntoView()}}function g(e){if(e.host===window.location.host&&!m.includes(e.pathname)){m.push(e.pathname);const o=document.createElement("link");o.setAttribute("as","fetch"),o.setAttribute("rel","prefetch"),o.setAttribute("href",origin+e.pathname+"/content.dat"),document.head.appendChild(o)}}function y(){m=[window.location.pathname],a=document.location.hash.replace(/^#/,"");const e=new Promise(function(t,n){document.addEventListener("DOMContentLoaded",r=>{t(u())})});typeof connect=="function"&&connect(function(t){e.then(n=>{n.ports.hotReloadData.send(t)})});const o=t=>{const n=w(t.target);n&&n.href&&n.hasAttribute("elm-pages:prefetch")&&g(n)};let i;const s=t=>{clearTimeout(i),i=setTimeout(()=>{o(t)},20)};addEventListener("touchstart",o),addEventListener("mousemove",s)}function w(e){for(;e&&e.nodeName.toUpperCase()!=="A";)e=e.parentNode;return e}y();
