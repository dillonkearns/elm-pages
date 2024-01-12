---
description: You can share `elm-pages` scripts hosted in GitHub Repos or Gists, and run them locally with a single command.
---

# Remote `elm-pages` Scripts

You can share `elm-pages` scripts hosted in GitHub Repos or Gists, and run them locally with a single command.

 ```
npx elm-pages@latest run https://github.com/dillonkearns/elm-pages-starter/blob/master/script/src/Stars.elm

622
```

Notice that the URL we pass in contains all the information to point to a specific elm-pages script module. And you can
even open that URL in your browser and see the file (and the script folder that module is a part of) that you are executing: <https://github.com/dillonkearns/elm-pages-starter/blob/master/script/src/Stars.elm>.

Several formats are supported for referring to a remote script to run. The most intuitive way is to use formats that correspond to the URL of
a raw file on GitHub as we did above. When you do this, it will find the nearest `elm.json` to that file automatically, and execute the `elm-pages` script module
that you specify.

You can also specify a specific commit hash or branch name in the URL. Let's execute the `Stars.elm` script from the `dillonkearns/elm-pages-starter` at a specific commit.

Because we're locking in a specific commit, let's also specify the version of `elm-pages` to use that corresponds with the `elm-pages` Elm package used in the script folder's elm.json at that commit (otherwise it would give an error telling us they are incompatible).

```
npx elm-pages@3.0.12 run https://github.com/dillonkearns/elm-pages-starter/blob/4bc22294053279418e37fae64a64125d6d116ded/script/src/Stars.elm
```

## Supported formats for remote scripts

Here is a list of all the supported formats for executing a remote script from a GitHub repo:

- `https://github.com/dillonkearns/elm-pages-starter/blob/master/script/src/Stars.elm`
- `https://github.com/dillonkearns/elm-pages-starter/blob/4bc22294053279418e37fae64a64125d6d116ded/script/src/Stars.elm`
- `https://raw.githubusercontent.com/dillonkearns/elm-pages-starter/master/script/src/Stars.elm`
- `https://raw.githubusercontent.com/dillonkearns/elm-pages-starter/blob/4bc22294053279418e37fae64a64125d6d116ded/script/src/Stars.elm`
- `github:dillonkearns/elm-pages-starter:script/src/Stars.elm`


## Running a remote script from a GitHub Gist:

You can also run a script from a GitHub Gist by passing in the URL to the gist. This is often a faster and easier way to create and share a simple script so it's a convenient method.

It will use the `elm.json` file for the script's dependencies, and execute `Main.elm` as the entrypoint script file. You can also `import` any other Elm modules into your `Main.elm` file. Instead of the convention `src` folder as the main entry of the `elm.json` `source-directories`, these Gists use `"."` (the top-level folder) as the source-directory because Gists are flat and have no folder structure.

Similar to the approach with GitHub repos, you specify a Gist URL which you could also open in your browser.

For example, you can look at this code in your browser: <https://gist.github.com/dillonkearns/4f050018784b25246729a82fc9907543>. And you can execute it by passing it to `elm-pages run`:

`npx elm-pages@3.0.12 run https://gist.github.com/dillonkearns/4f050018784b25246729a82fc9907543`

You can specify an entrypoint file to execute from a Gist by linking to a raw file in a Gist directly like so:

<https://gist.githubusercontent.com/dillonkearns/4f050018784b25246729a82fc9907543/raw/898c6963b87b37d026f162f5758ad7a23825cd64/Main.elm>

`npx elm-pages@3.0.12 run https://gist.githubusercontent.com/dillonkearns/4f050018784b25246729a82fc9907543/raw/898c6963b87b37d026f162f5758ad7a23825cd64/Main.elm`

You can use this to either explicitly point to the default entrypoint `Main.elm`, or to execute a different entrypoint script.
