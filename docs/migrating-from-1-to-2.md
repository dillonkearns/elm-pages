# Migrating From 1 to 2.0 beta

Note: these instruactions are for the public beta.

## Clone Repo

```shell
git submodule add -b static-files https://github.com/dillonkearns/elm-pages.git
```

Add `"elm-pages/src"` to your `source-directories` in your `elm.json`. Delete the files that `elm-pages` generated in the `gen` folder, or remove it entirely and delete `"gen"` from `source-directories`.

## Install Dependencies

If you'd like to migrate with the beta, you'll need to manually make sure you have these dependencies installed since Elm doesn't have a way to publish beta release packages.

```shell
npm i -g elm-json
elm-json install avh4/elm-color@1.0.0 danyx23/elm-mimetype@4.0.1 dillonkearns/elm-bcp47-language-tag@1.0.1 elm/browser@1.0.2 elm/core@1.0.5 elm/html@1.0.0 elm/http@2.0.0 elm/json@1.1.3 elm/regex@1.0.0 elm/url@1.0.0 elm-community/dict-extra@2.4.0 elm-community/list-extra@8.3.0 miniBill/elm-codec@2.0.0 noahzgordon/elm-color-extra@1.0.2 tripokey/elm-fuzzy@5.2.1 zwilias/json-decode-exploration@6.0.0
```

There is no `static` or `images` folder in `elm-pages` 2.0, just a single `public/` folder with no special post-processing.

```shell
mv static public
mv images public/images
```
