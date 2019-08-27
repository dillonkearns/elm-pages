---
title: File Structure
type: doc
---

## Philosophy

As a general rule, `elm-pages` strives to be unopinionated about how you organize
your files (both code and content).

```shell
.
├── content/
├── elm.json
├── images/
├── static/
├── index.js
├── package.json
└── src/
    └── Main.elm
```

## `content` folder

Each file in the `content` folder will result in a new route for your static site.
The accepted formats currently are:

- `.emu` (`elm-markup`)
- `.md` (Markdown)

## Metadata
