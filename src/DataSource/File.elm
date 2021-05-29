module DataSource.File exposing
    ( bodyWithFrontmatter, bodyWithoutFrontmatter, onlyFrontmatter
    , jsonFile, rawFile
    )

{-| This module lets you read files from the local filesystem as a [`DataSource`](DataSource#DataSource).


## Files With Frontmatter

Frontmatter is a convention used to keep metadata at the top of a file between `---`'s.

For example, you might have a file called `blog/hello-world.md` with this content:

```markdown
---
title: Hello, World!
draft: true
---
Hey there! This is my first post :)
```

The frontmatter is in the [YAML format](https://en.wikipedia.org/wiki/YAML) here. You can also use JSON in your elm-pages frontmatter.

```markdown
---
{"title": "Hello, World!", "draft": true}
---
Hey there! This is my first post :)
```

Whether it's YAML or JSON, you use an `OptimizedDecoder` to decode your frontmatter, so it feels just like using
plain old JSON in Elm.

@docs bodyWithFrontmatter, bodyWithoutFrontmatter, onlyFrontmatter


## Reading Files Without Frontmatter

@docs jsonFile, rawFile

-}

import DataSource exposing (DataSource)
import DataSource.Http
import OptimizedDecoder exposing (Decoder)
import Secrets


frontmatter : Decoder frontmatter -> Decoder frontmatter
frontmatter frontmatterDecoder =
    OptimizedDecoder.field "parsedFrontmatter" frontmatterDecoder


{-|

    import DataSource exposing (DataSource)
    import DataSource.File as File
    import OptimizedDecoder as Decode exposing (Decoder)

    blogPost : DataSource ( String, BlogPostMetadata )
    blogPost =
        File.bodyWithFrontmatter "blog/hello-world.md"
            blogPostDecoder

    type alias BlogPostMetadata =
        { body : String
        , title : String
        , draft : Bool
        }

    blogPostDecoder : Decoder BlogPostMetadata
    blogPostDecoder body =
        Decode.map2 (BlogPostMetadata body)
            (Decode.field "title" Decode.string)
            (Decode.field "draft" Decode.bool)

This will give us a DataSource that results in the following value:

    value =
        { body = "Hey there! This is my first post :)"
        , title = "Hello, World!"
        , draft = True
        }

It's common to parse the body with a markdown parser or other format.

    import DataSource exposing (DataSource)
    import DataSource.File as File
    import Html exposing (Html)
    import OptimizedDecoder as Decode exposing (Decoder)

    example :
        DataSource
            { title : String
            , body : List (Html msg)
            }
    example =
        File.bodyWithFrontmatter "foo.md"
            (\markdownString ->
                Decode.map2
                    (\title renderedMarkdown ->
                        { title = title
                        , body = renderedMarkdown
                        }
                    )
                    (Decode.field "title" Decode.string)
                    (markdownString
                        |> markdownToView
                        |> Decode.fromResult
                    )
            )

    markdownToView :
        String
        -> Result String (List (Html msg))
    markdownToView markdownString =
        markdownString
            |> Markdown.Parser.parse
            |> Result.mapError (\_ -> "Markdown error.")
            |> Result.andThen
                (\blocks ->
                    Markdown.Renderer.render
                        Markdown.Renderer.defaultHtmlRenderer
                        blocks
                )

-}
bodyWithFrontmatter : String -> (String -> Decoder frontmatter) -> DataSource frontmatter
bodyWithFrontmatter filePath frontmatterDecoder =
    read filePath
        (body
            |> OptimizedDecoder.andThen
                (\bodyString ->
                    frontmatter (frontmatterDecoder bodyString)
                )
        )


{-| Same as `bodyWithFrontmatter` except it doesn't include the body.

This is often useful when you're aggregating data, for example getting a listing of blog posts and need to extract
just the metadata.

    import DataSource exposing (DataSource)
    import DataSource.File as File
    import OptimizedDecoder as Decode exposing (Decoder)

    blogPost : DataSource BlogPostMetadata
    blogPost =
        File.onlyFrontmatter "blog/hello-world.md"
            blogPostDecoder

    type alias BlogPostMetadata =
        { title : String
        , tags : List String
        }

    blogPostDecoder : Decoder BlogPostMetadata
    blogPostDecoder =
        Decode.map2 BlogPostMetadata
            (Decode.field "title" Decode.string)
            (Decode.field "tags" (Decode.list Decode.string))

If you wanted to use this to get this metadata for all blog posts in a folder, you could use
the [`DataSource`](DataSource) API along with [`DataSource.Glob`](DataSource.Glob).

    import DataSource exposing (DataSource)
    import DataSource.File as File
    import OptimizedDecoder as Decode exposing (Decoder)

    blogPostFiles : DataSource (List String)
    blogPostFiles =
        Glob.succeed identity
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "content/blog/")
            |> Glob.match Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toDataSource

    allMetadata : DataSource (List BlogPostMetadata)
    allMetadata =
        blogPostFiles
            |> DataSource.map
                (List.map
                    (\filePath ->
                        File.onlyFrontmatter
                            filePath
                            blogPostDecoder
                    )
                )
            |> DataSource.resolve

-}
onlyFrontmatter : String -> Decoder frontmatter -> DataSource frontmatter
onlyFrontmatter filePath frontmatterDecoder =
    read filePath
        (frontmatter frontmatterDecoder)


{-| Same as `bodyWithFrontmatter` except it doesn't include the frontmatter.

For example, if you have a file called `blog/hello-world.md` with

```markdown
---
{"title": "Hello, World!", "draft": true}
---
Hey there! This is my first post :)
```

    import DataSource exposing (DataSource)

    data : DataSource String
    data =
        bodyWithoutFrontmatter "blog/hello-world.md"

Then data will yield the value `"Hey there! This is my first post :)"`.

-}
bodyWithoutFrontmatter : String -> DataSource String
bodyWithoutFrontmatter filePath =
    read filePath
        body


{-| Get the raw file content. Unlike the frontmatter helpers in this module, this function will not strip off frontmatter if there is any.

This is the function you want if you are reading in a file directly. For example, if you read in a CSV file, a raw text file, or any other file that doesn't
have frontmatter.

There's a special function for reading in JSON files, [`jsonFile`](#jsonFile). If you're reading a JSON file then be sure to
use `jsonFile` to get the benefits of the `OptimizedDecoder` here.

-}
rawFile : String -> DataSource String
rawFile filePath =
    read filePath (OptimizedDecoder.field "rawFile" OptimizedDecoder.string)


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
