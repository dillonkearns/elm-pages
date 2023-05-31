module BackendTask.File exposing
    ( bodyWithFrontmatter, bodyWithoutFrontmatter, onlyFrontmatter
    , jsonFile, rawFile
    , FileReadError(..)
    )

{-| This module lets you read files from the local filesystem as a [`BackendTask`](BackendTask#BackendTask).
File paths are relative to the root of your `elm-pages` project (next to the `elm.json` file and `src/` directory).


## Files With Frontmatter

Frontmatter is a convention used to keep metadata at the top of a file between `---`'s.

For example, you might have a file called `blog/hello-world.md` with this content:

```markdown
---
title: Hello, World!
tags: elm
---
Hey there! This is my first post :)
```

The frontmatter is in the [YAML format](https://en.wikipedia.org/wiki/YAML) here. You can also use JSON in your elm-pages frontmatter.

```markdown
---
{"title": "Hello, World!", "tags": "elm"}
---
Hey there! This is my first post :)
```

Whether it's YAML or JSON, you use an `Decode` to decode your frontmatter, so it feels just like using
plain old JSON in Elm.

@docs bodyWithFrontmatter, bodyWithoutFrontmatter, onlyFrontmatter


## Reading Files Without Frontmatter

@docs jsonFile, rawFile


## FatalErrors

@docs FileReadError

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)
import TerminalText


frontmatter : Decoder frontmatter -> Decoder frontmatter
frontmatter frontmatterDecoder =
    Decode.field "parsedFrontmatter" frontmatterDecoder


{-|

    import BackendTask exposing (BackendTask)
    import BackendTask.File as File
    import Decode exposing (Decoder)

    blogPost : BackendTask BlogPostMetadata
    blogPost =
        File.bodyWithFrontmatter blogPostDecoder
            "blog/hello-world.md"

    type alias BlogPostMetadata =
        { body : String
        , title : String
        , tags : List String
        }

    blogPostDecoder : String -> Decoder BlogPostMetadata
    blogPostDecoder body =
        Decode.map2 (BlogPostMetadata body)
            (Decode.field "title" Decode.string)
            (Decode.field "tags" tagsDecoder)

    tagsDecoder : Decoder (List String)
    tagsDecoder =
        Decode.map (String.split " ")
            Decode.string

This will give us a BackendTask that results in the following value:

    value =
        { body = "Hey there! This is my first post :)"
        , title = "Hello, World!"
        , tags = [ "elm" ]
        }

It's common to parse the body with a markdown parser or other format.

    import BackendTask exposing (BackendTask)
    import BackendTask.File as File
    import Decode exposing (Decoder)
    import Html exposing (Html)

    example :
        BackendTask
            { title : String
            , body : List (Html msg)
            }
    example =
        File.bodyWithFrontmatter
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
            "foo.md"

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
bodyWithFrontmatter :
    (String -> Decoder frontmatter)
    -> String
    ->
        BackendTask
            { fatal : FatalError
            , recoverable : FileReadError Decode.Error
            }
            frontmatter
bodyWithFrontmatter frontmatterDecoder filePath =
    BackendTask.Internal.Request.request2
        { name = "read-file"
        , body = BackendTask.Http.stringBody "" filePath
        , expect =
            body
                |> Decode.andThen
                    (\bodyString ->
                        frontmatter (frontmatterDecoder bodyString)
                    )
        , errorDecoder = Decode.field "errorCode" (errorDecoder filePath)
        , onError =
            \frontmatterDecodeError ->
                { fatal =
                    { title = "BackendTask.File Decoder Error"
                    , body =
                        "I encountered a Json Decoder error from a call to BackendTask.File.bodyWithFrontmatter.\n\n"
                            ++ Decode.errorToString frontmatterDecodeError
                    }
                        |> FatalError.build
                , recoverable = DecodingError frontmatterDecodeError
                }
        }


{-| -}
type FileReadError decoding
    = FileDoesntExist
    | FileReadError String
    | DecodingError decoding


{-| Same as `bodyWithFrontmatter` except it doesn't include the body.

This is often useful when you're aggregating data, for example getting a listing of blog posts and need to extract
just the metadata.

    import BackendTask exposing (BackendTask)
    import BackendTask.File as File
    import Decode exposing (Decoder)

    blogPost : BackendTask BlogPostMetadata
    blogPost =
        File.onlyFrontmatter
            blogPostDecoder
            "blog/hello-world.md"

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
the [`BackendTask`](BackendTask) API along with [`BackendTask.Glob`](BackendTask-Glob).

    import BackendTask exposing (BackendTask)
    import BackendTask.File as File
    import Decode exposing (Decoder)

    blogPostFiles : BackendTask (List String)
    blogPostFiles =
        Glob.succeed identity
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "content/blog/")
            |> Glob.match Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

    allMetadata : BackendTask (List BlogPostMetadata)
    allMetadata =
        blogPostFiles
            |> BackendTask.map
                (List.map
                    (File.onlyFrontmatter
                        blogPostDecoder
                    )
                )
            |> BackendTask.resolve

-}
onlyFrontmatter :
    Decoder frontmatter
    -> String
    ->
        BackendTask
            { fatal : FatalError
            , recoverable : FileReadError Decode.Error
            }
            frontmatter
onlyFrontmatter frontmatterDecoder filePath =
    BackendTask.Internal.Request.request2
        { name = "read-file"
        , body = BackendTask.Http.stringBody "" filePath
        , expect = frontmatter frontmatterDecoder
        , errorDecoder = Decode.field "errorCode" (errorDecoder filePath)
        , onError =
            \frontmatterDecodeError ->
                { fatal =
                    { title = "BackendTask.File Decoder Error"
                    , body =
                        "I encountered a Json Decoder error from a call to BackendTask.File.onlyFrontmatter.\n\n"
                            ++ Decode.errorToString frontmatterDecodeError
                    }
                        |> FatalError.build
                , recoverable = DecodingError frontmatterDecodeError
                }
        }


{-| Same as `bodyWithFrontmatter` except it doesn't include the frontmatter.

For example, if you have a file called `blog/hello-world.md` with

```markdown
---
title: Hello, World!
tags: elm
---
Hey there! This is my first post :)
```

    import BackendTask exposing (BackendTask)

    data : BackendTask String
    data =
        bodyWithoutFrontmatter "blog/hello-world.md"

Then data will yield the value `"Hey there! This is my first post :)"`.

-}
bodyWithoutFrontmatter :
    String
    ->
        BackendTask
            { fatal : FatalError
            , recoverable : FileReadError decoderError
            }
            String
bodyWithoutFrontmatter filePath =
    read filePath
        body


{-| Get the raw file content. Unlike the frontmatter helpers in this module, this function will not strip off frontmatter if there is any.

This is the function you want if you are reading in a file directly. For example, if you read in a CSV file, a raw text file, or any other file that doesn't
have frontmatter.

There's a special function for reading in JSON files, [`jsonFile`](#jsonFile). If you're reading a JSON file then be sure to
use `jsonFile` to get the benefits of the `Decode` here.

You could read a file called `hello.txt` in your root project directory like this:

    import BackendTask exposing (BackendTask)
    import BackendTask.File as File

    elmJsonFile : BackendTask String
    elmJsonFile =
        File.rawFile "hello.txt"

-}
rawFile : String -> BackendTask { fatal : FatalError, recoverable : FileReadError decoderError } String
rawFile filePath =
    read filePath (Decode.field "rawFile" Decode.string)


{-| Read a file as JSON.

The Decode will strip off any unused JSON data.

    import BackendTask exposing (BackendTask)
    import BackendTask.File as File

    sourceDirectories : BackendTask (List String)
    sourceDirectories =
        File.jsonFile
            (Decode.field
                "source-directories"
                (Decode.list Decode.string)
            )
            "elm.json"

-}
jsonFile :
    Decoder a
    -> String
    ->
        BackendTask
            { fatal : FatalError
            , recoverable : FileReadError Decode.Error
            }
            a
jsonFile jsonFileDecoder filePath =
    rawFile filePath
        |> BackendTask.andThen
            (\jsonString ->
                jsonString
                    |> Decode.decodeString jsonFileDecoder
                    |> Result.mapError
                        (\jsonDecodeError ->
                            FatalError.recoverable
                                { title = "JSON Decoding Error"
                                , body =
                                    [ TerminalText.text (Decode.errorToString jsonDecodeError)
                                    ]
                                        |> TerminalText.toString
                                }
                                (DecodingError jsonDecodeError)
                        )
                    |> BackendTask.fromResult
            )


{-| Gives us the file's content without stripping off frontmatter.
-}
body : Decoder String
body =
    Decode.field "withoutFrontmatter" Decode.string


read : String -> Decoder a -> BackendTask { fatal : FatalError, recoverable : FileReadError error } a
read filePath decoder =
    BackendTask.Internal.Request.request
        { name = "read-file"
        , body = BackendTask.Http.stringBody "" filePath
        , expect =
            Decode.oneOf
                [ Decode.field "errorCode"
                    (Decode.map Err (errorDecoder filePath))
                , decoder |> Decode.map Ok
                ]
                |> BackendTask.Http.expectJson
        }
        |> BackendTask.andThen BackendTask.fromResult


errorDecoder :
    String
    ->
        Decoder
            { fatal : FatalError
            , recoverable : FileReadError decoding
            }
errorDecoder filePath =
    Decode.succeed
        (FatalError.recoverable
            { title = "File Doesn't Exist"
            , body =
                [ TerminalText.text "Couldn't find file at path `"
                , TerminalText.yellow filePath
                , TerminalText.text "`"
                ]
                    |> TerminalText.toString
            }
            FileDoesntExist
        )
