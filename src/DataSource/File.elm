module DataSource.File exposing
    ( read
    , body, frontmatter
    , jsonFile, rawFile
    )

{-| This module lets you read files from the local filesystem as a [`DataSource`](DataSource#DataSource).

@docs read


## Reading Frontmatter

@docs body, frontmatter


## Reading Files

@docs jsonFile, rawFile

-}

import DataSource exposing (DataSource)
import DataSource.Http
import OptimizedDecoder exposing (Decoder)
import Secrets


{-| Frontmatter is a convention used to keep metadata in a file between `---`'s.

For example, you might have a file called `blog/hello-world.md` with this content:

```markdown
---
title: Hello, World!
draft: true
---
Hey there! This is my first post :)
```

The frontmatter is in the [YAML format](https://en.wikipedia.org/wiki/YAML) here.
You can also use JSON in your elm-pages frontmatter.

Whether it's YAML or JSON, you use an `OptimizedDecoder` to decode your frontmatter, so it feels just like using
plain old JSON in Elm.

    import DataSource exposing (DataSource)
    import DataSource.File as File
    import OptimizedDecoder as Decode exposing (Decoder)

    blogPost : DataSource ( String, BlogPostMetadata )
    blogPost =
        File.read "blog/hello-world.md"
            (Decode.map2 Tuple.pair
                (File.frontmatter blogPostDecoder)
                File.body
            )

    type alias BlogPostMetadata =
        { title : String
        , draft : Bool
        }

    blogPostDecoder : Decoder BlogPostMetadata
    blogPostDecoder =
        Decode.map2 BlogPostMetadata
            (Decode.field "title" Decode.string)
            (Decode.field "draft" Decode.bool)

This will give us a DataSource that results in the following value:

    value =
        ( "Hey there! This is my first post :)"
        , { title = "Hello, World!"
          , draft = True
          }
        )

-}
frontmatter : Decoder frontmatter -> Decoder frontmatter
frontmatter frontmatterDecoder =
    OptimizedDecoder.field "parsedFrontmatter" frontmatterDecoder


{-| Gives us the file's content without stripping off frontmatter.
-}
rawFile : Decoder String
rawFile =
    OptimizedDecoder.field "rawFile" OptimizedDecoder.string


{-| Read a file as JSON.

The OptimizedDecoder will strip off any unused JSON data.

-}
jsonFile : String -> Decoder a -> DataSource a
jsonFile filePath jsonFileDecoder =
    read filePath (OptimizedDecoder.field "jsonFile" jsonFileDecoder)


{-| Gives us the file's content without stripping off frontmatter.
-}
body : Decoder String
body =
    OptimizedDecoder.field "withoutFrontmatter" OptimizedDecoder.string


{-| Read a file in as a [`DataSource`](DataSource#DataSource). You can directly read a file path,
relative to the root of your `elm-pages` project (next to the `elm.json` file and `src/` directory).

You could read your `elm.json` file in your project like this:

    import DataSource exposing (DataSource)
    import DataSource.File as File

    elmJsonFile : DataSource String
    elmJsonFile =
        File.read "elm.json" File.rawFile

The `OptimizedDecoder.Decoder` argument can use any of the `Decoder` types in this module:

  - [`rawBody`](#rawBody)
  - [`body`](#body)
  - [`frontmatter`](#frontmatter)

Often you'll want to combine two together. For example, if you're reading the `frontmatter` and `body` from a file
(see the example for [`frontmatter`](#frontmatter)).

-}
read : String -> Decoder a -> DataSource a
read filePath =
    DataSource.Http.get (Secrets.succeed <| "file://" ++ filePath)
