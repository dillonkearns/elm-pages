# Ports and Flags

You can handle ports and flags similar to how you would in a regular Elm application.

There are two main differences. First, the wiring goes through the default export in the `index.js` file, like this example.

```javascript
export default {
  load: async function (elmLoaded) {
    const app = await elmLoaded;
    console.log("App loaded", app);
    // you can call your custom ports here
    app.ports.readLocalStorage.subscribe((localStorageKey) => {
      app.ports.gotLocalStorage.send(localStorage.getItem(localStorageKey));
    });
  },
  flags: function () {
    return "You can decode this in Shared.elm using Json.Decode.string!";
  },
};
```

The second difference is that you need to handle an additional state for flags. In a regular Elm application, you can use flags to get initial data into your `Model` to make sure it's there on `init`. That way, you can reduce `Maybe` values in your `Model`, and reduce any flashing view state from initial state coming in after the first `view` render.

This is a great idea for an `elm-pages` app as well. However, in an `elm-pages` you need to give an initial state that is independent of the user's Browser session because `elm-pages` pre-renders pages for you. That means that it builds HTML for all of your pre-rendered routes before the user has even hit the URL to load your page!

In order to have a seamless transition from the pre-rendered HTML to the hydrated Elm app that takes over after the initial render, it's best to avoid depending on the state of the user's browser for the initial view.

## Avoiding Flash with elm-ui

`elm-pages` users who render their views with `elm-ui` often ask how they can get the initial browser window dimensions in their flags. You can get this in your flags, but again you will still need to handle the pre-rendered view before you have these flags, so you can't rely on this to avoid layout shifts.

The ideal solution is to use the web platforms solutions for this, like media queries, because this is a declarative way of making pages responsive that doesn't rely on JavaScript (or Elm) executing. `elm-ui` doesn't currently have first-class support for media queries, but it's possible to use media queries with elm-ui using some clever workarounds.

In your stylesheet, you can hide elements with a given CSS class depending on the screen width, like so:

```css
@media (max-width: 600px) {
  .responsive-desktop {
    display: none !important;
  }
}
@media (min-width: 600px) {
  .responsive-mobile {
    display: none !important;
  }
}
```

Now you can render two views, and the media query will hide them based on the browser window's width:

```elm
Element.htmlAttribute (Attr.class "responsive-mobile")
```
