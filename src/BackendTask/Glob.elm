module BackendTask.Glob exposing
    ( Glob
    , capture, match
    , captureFilePath
    , wildcard, recursiveWildcard
    , int, digits
    , FileStats, captureStats
    , expectUniqueMatch, expectUniqueMatchFromList
    , literal
    , map, succeed
    , oneOf
    , zeroOrMore, atLeastOne
    , toBackendTask
    , toBackendTaskWithOptions
    , defaultOptions, Options, Include(..)
    )

{-|

@docs Glob

This module helps you get a List of matching file paths from your local file system as a [`BackendTask`](BackendTask#BackendTask). See the [`BackendTask`](BackendTask) module documentation
for ways you can combine and map `BackendTask`s.

A common example would be to find all the markdown files of your blog posts. If you have all your blog posts in `content/blog/*.md`
, then you could use that glob pattern in most shells to refer to each of those files.

With the `BackendTask.Glob` API, you could get all of those files like so:

    import BackendTask exposing (BackendTask)

    blogPostsGlob : BackendTask error (List String)
    blogPostsGlob =
        Glob.succeed (\slug -> slug)
            |> Glob.match (Glob.literal "content/blog/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

Let's say you have these files locally:

```shell
- elm.json
- src/
- content/
  - blog/
    - first-post.md
    - second-post.md
```

We would end up with a `BackendTask` like this:

    BackendTask.succeed [ "first-post", "second-post" ]

Of course, if you add or remove matching files, the BackendTask will get those new files (unlike `BackendTask.succeed`). That's why we have Glob!

You can even see the `elm-pages dev` server will automatically flow through any added/removed matching files with its hot module reloading.

But why did we get `"first-post"` instead of a full file path, like `"content/blog/first-post.md"`? That's the difference between
`capture` and `match`.


## Capture and Match

There are two functions for building up a Glob pattern: `capture` and `match`.

`capture` and `match` both build up a `Glob` pattern that will match 0 or more files on your local file system.
There will be one argument for every `capture` in your pipeline, whereas `match` does not apply any arguments.

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    blogPostsGlob : BackendTask error (List String)
    blogPostsGlob =
        Glob.succeed (\slug -> slug)
            -- no argument from this, but we will only
            -- match files that begin with `content/blog/`
            |> Glob.match (Glob.literal "content/blog/")
            -- we get the value of the `wildcard`
            -- as the slug argument
            |> Glob.capture Glob.wildcard
            -- no argument from this, but we will only
            -- match files that end with `.md`
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

So to understand _which_ files will match, you can ignore whether you are using `capture` or `match` and just read
the patterns you're using in order to understand what will match. To understand what Elm data type you will get
_for each matching file_, you need to see which parts are being captured and how each of those captured values are being
used in the function you use in `Glob.succeed`.

@docs capture, match

`capture` is a lot like building up a JSON decoder with a pipeline.

Let's try our blogPostsGlob from before, but change every `match` to `capture`.

    import BackendTask exposing (BackendTask)

    blogPostsGlob :
        BackendTask
            error
            (List
                { filePath : String
                , slug : String
                }
            )
    blogPostsGlob =
        Glob.succeed
            (\capture1 capture2 capture3 ->
                { filePath = capture1 ++ capture2 ++ capture3
                , slug = capture2
                }
            )
            |> Glob.capture (Glob.literal "content/blog/")
            |> Glob.capture Glob.wildcard
            |> Glob.capture (Glob.literal ".md")
            |> Glob.toBackendTask

Notice that we now need 3 arguments at the start of our pipeline instead of 1. That's because
we apply 1 more argument every time we do a `Glob.capture`, much like `Json.Decode.Pipeline.required`, or other pipeline APIs.

Now we actually have the full file path of our files. But having that slug (like `first-post`) is also very helpful sometimes, so
we kept that in our record as well. So we'll now have the equivalent of this `BackendTask` with the current `.md` files in our `blog` folder:

    BackendTask.succeed
        [ { filePath = "content/blog/first-post.md"
          , slug = "first-post"
          }
        , { filePath = "content/blog/second-post.md"
          , slug = "second-post"
          }
        ]

Having the full file path lets us read in files. But concatenating it manually is tedious
and error prone. That's what the [`captureFilePath`](#captureFilePath) helper is for.


## Reading matching files

@docs captureFilePath

In many cases you will want to take the matching files from a `Glob` and then read the body or frontmatter from matching files.


## Reading Metadata for each Glob Match

For example, if we had files like this:

```markdown
---
title: My First Post
---
This is my first post!
```

Then we could read that title for our blog post list page using our `blogPosts` `BackendTask` that we defined above.

    import BackendTask.File
    import FatalError exposing (FatalError)
    import Json.Decode as Decode exposing (Decoder)

    titles : BackendTask FatalError (List BlogPost)
    titles =
        blogPosts
            |> BackendTask.map
                (List.map
                    (\blogPost ->
                        BackendTask.File.onlyFrontmatter
                            blogFrontmatterDecoder
                            blogPost.filePath
                    )
                )
            |> BackendTask.resolve
            |> BackendTask.allowFatal

    type alias BlogPost =
        { title : String }

    blogFrontmatterDecoder : Decoder BlogPost
    blogFrontmatterDecoder =
        Decode.map BlogPost
            (Decode.field "title" Decode.string)

That will give us

    BackendTask.succeed
        [ { title = "My First Post" }
        , { title = "My Second Post" }
        ]


## Capturing Patterns

@docs wildcard, recursiveWildcard


## Capturing Specific Characters

@docs int, digits


## Capturing File Stats

You can access a file's stats including timestamps when the file was created and modified, and file size.

@docs FileStats, captureStats


## Matching a Specific Number of Files

@docs expectUniqueMatch, expectUniqueMatchFromList


## Glob Patterns

@docs literal

@docs map, succeed

@docs oneOf

@docs zeroOrMore, atLeastOne


## Getting Glob Data from a BackendTask

@docs toBackendTask


### With Custom Options

@docs toBackendTaskWithOptions

@docs defaultOptions, Options, Include

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Glob exposing (Glob(..))
import BackendTask.Internal.Request
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import List.Extra
import Time


{-| A pattern to match local files and capture parts of the path into a nice Elm data type.
-}
type alias Glob a =
    BackendTask.Internal.Glob.Glob a


{-| A `Glob` can be mapped. This can be useful for transforming a sub-match in-place.

For example, if you wanted to take the slugs for a blog post and make sure they are normalized to be all lowercase, you
could use

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    blogPostsGlob : BackendTask error (List String)
    blogPostsGlob =
        Glob.succeed (\slug -> slug)
            |> Glob.match (Glob.literal "content/blog/")
            |> Glob.capture (Glob.wildcard |> Glob.map String.toLower)
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

If you want to validate file formats, you can combine that with some `BackendTask` helpers to turn a `Glob (Result String value)` into
a `BackendTask FatalError (List value)`.

For example, you could take a date and parse it.

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    example : BackendTask FatalError (List ( String, String ))
    example =
        Glob.succeed
            (\dateResult slug ->
                dateResult
                    |> Result.map (\okDate -> ( okDate, slug ))
            )
            |> Glob.match (Glob.literal "blog/")
            |> Glob.capture (Glob.recursiveWildcard |> Glob.map expectDateFormat)
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask
            |> BackendTask.map (List.map BackendTask.fromResult)
            |> BackendTask.resolve

    expectDateFormat : List String -> Result FatalError String
    expectDateFormat dateParts =
        case dateParts of
            [ year, month, date ] ->
                Ok (String.join "-" [ year, month, date ])

            _ ->
                Err <| FatalError.fromString "Unexpected date format, expected yyyy/mm/dd folder structure."

-}
map : (a -> b) -> Glob a -> Glob b
map mapFn (Glob pattern applyCapture) =
    Glob pattern
        (\fileStats fullPath captures ->
            captures
                |> applyCapture fileStats fullPath
                |> Tuple.mapFirst mapFn
        )


{-| `succeed` is how you start a pipeline for a `Glob`. You will need one argument for each `capture` in your `Glob`.
-}
succeed : constructor -> Glob constructor
succeed constructor =
    Glob "" (\_ _ captures -> ( constructor, captures ))


fullFilePath : Glob String
fullFilePath =
    Glob ""
        (\_ fullPath captures ->
            ( fullPath, captures )
        )


{-|

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    blogPosts :
        BackendTask
            error
            (List
                { filePath : String
                , slug : String
                }
            )
    blogPosts =
        Glob.succeed
            (\filePath slug ->
                { filePath = filePath
                , slug = slug
                }
            )
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "content/blog/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

This function does not change which files will or will not match. It just gives you the full matching
file path in your `Glob` pipeline.

Whenever possible, it's a good idea to use function to make sure you have an accurate file path when you need to read a file.

-}
captureFilePath : Glob (String -> value) -> Glob value
captureFilePath =
    capture fullFilePath


{-| The information about a file that you can access when you use [`captureStats`](#captureStats).
-}
type alias FileStats =
    { fullPath : String
    , sizeInBytes : Int
    , lastContentChange : Time.Posix
    , lastAccess : Time.Posix
    , lastFileChange : Time.Posix
    , createdAt : Time.Posix
    , isDirectory : Bool
    }


{-|

    import BackendTask.Glob as Glob

    recentlyChangedRouteModules : BackendTask error (List ( Time.Posix, List String ))
    recentlyChangedRouteModules =
        Glob.succeed
            (\fileStats directoryName fileName ->
                ( fileStats.lastContentChange
                , directoryName ++ [ fileName ]
                )
            )
            |> Glob.captureStats
            |> Glob.match (Glob.literal "app/Route/")
            |> Glob.capture Glob.recursiveWildcard
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".elm")
            |> Glob.toBackendTask
            |> BackendTask.map
                (\entries ->
                    entries
                        |> List.sortBy (\( lastChanged, _ ) -> Time.posixToMillis lastChanged)
                        |> List.reverse
                )

-}
captureStats : Glob (FileStats -> value) -> Glob value
captureStats =
    capture
        (Glob ""
            (\fileStats _ captures ->
                ( fileStats
                    |> Maybe.withDefault
                        { fullPath = "ERROR"
                        , sizeInBytes = -1
                        , lastContentChange = Time.millisToPosix 0
                        , lastAccess = Time.millisToPosix 0
                        , lastFileChange = Time.millisToPosix 0
                        , createdAt = Time.millisToPosix 0
                        , isDirectory = True
                        }
                , captures
                )
            )
        )


fullStats : Glob String
fullStats =
    Glob ""
        (\fileStats fullPath captures ->
            ( fullPath, captures )
        )


{-| Matches anything except for a `/` in a file path. You may be familiar with this syntax from shells like bash
where you can run commands like `rm client/*.js` to remove all `.js` files in the `client` directory.

Just like a `*` glob pattern in bash, this `Glob.wildcard` function will only match within a path part. If you need to
match 0 or more path parts like, see `recursiveWildcard`.

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    type alias BlogPost =
        { year : String
        , month : String
        , day : String
        , slug : String
        }

    example : BackendTask error (List BlogPost)
    example =
        Glob.succeed BlogPost
            |> Glob.match (Glob.literal "blog/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal "-")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal "-")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

```shell

- blog/
  - 2021-05-27/
    - first-post.md
```

That will match to:

    results : BackendTask error (List BlogPost)
    results =
        BackendTask.succeed
            [ { year = "2021"
              , month = "05"
              , day = "27"
              , slug = "first-post"
              }
            ]

Note that we can "destructure" the date part of this file path in the format `yyyy-mm-dd`. The `wildcard` matches
will match _within_ a path part (think between the slashes of a file path). `recursiveWildcard` can match across path parts.

-}
wildcard : Glob String
wildcard =
    Glob "*"
        (\_ _ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


{-| This is similar to [`wildcard`](#wildcard), but it will only match 1 or more digits (i.e. `[0-9]+`).

See [`int`](#int) for a convenience function to get an Int value instead of a String of digits.

-}
digits : Glob String
digits =
    Glob "([0-9]+)"
        (\_ _ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


{-| Same as [`digits`](#digits), but it safely turns the digits String into an `Int`.

Leading 0's are ignored.

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    slides : BackendTask error (List Int)
    slides =
        Glob.succeed identity
            |> Glob.match (Glob.literal "slide-")
            |> Glob.capture Glob.int
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

With files

```shell
- slide-no-match.md
- slide-.md
- slide-1.md
- slide-01.md
- slide-2.md
- slide-03.md
- slide-4.md
- slide-05.md
- slide-06.md
- slide-007.md
- slide-08.md
- slide-09.md
- slide-10.md
- slide-11.md
```

Yields

    matches : BackendTask error (List Int)
    matches =
        BackendTask.succeed
            [ 1
            , 1
            , 2
            , 3
            , 4
            , 5
            , 6
            , 7
            , 8
            , 9
            , 10
            , 11
            ]

Note that neither `slide-no-match.md` nor `slide-.md` match.
And both `slide-1.md` and `slide-01.md` match and turn into `1`.

-}
int : Glob Int
int =
    digits
        |> map
            (\matchedDigits ->
                matchedDigits
                    |> String.toInt
                    |> Maybe.withDefault -1
            )


{-| Matches any number of characters, including `/`, as long as it's the only thing in a path part.

In contrast, `wildcard` will never match `/`, so it only matches within a single path part.

This is the elm-pages equivalent of `**/*.txt` in standard shell syntax:

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    example : BackendTask error (List ( List String, String ))
    example =
        Glob.succeed Tuple.pair
            |> Glob.match (Glob.literal "articles/")
            |> Glob.capture Glob.recursiveWildcard
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".txt")
            |> Glob.toBackendTask

With these files:

```shell
- articles/
  - google-io-2021-recap.txt
  - archive/
    - 1977/
      - 06/
        - 10/
          - apple-2-announced.txt
```

We would get the following matches:

    matches : BackendTask error (List ( List String, String ))
    matches =
        BackendTask.succeed
            [ ( [ "archive", "1977", "06", "10" ], "apple-2-announced" )
            , ( [], "google-io-2021-recap" )
            ]

Note that the recursive wildcard conveniently gives us a `List String`, where
each String is a path part with no slashes (like `archive`).

And also note that it matches 0 path parts into an empty list.

If we didn't include the `wildcard` after the `recursiveWildcard`, then we would only get
a single level of matches because it is followed by a file extension.

    example : BackendTask error (List String)
    example =
        Glob.succeed identity
            |> Glob.match (Glob.literal "articles/")
            |> Glob.capture Glob.recursiveWildcard
            |> Glob.match (Glob.literal ".txt")

    matches : BackendTask error (List String)
    matches =
        BackendTask.succeed
            [ "google-io-2021-recap"
            ]

This is usually not what is intended. Using `recursiveWildcard` is usually followed by a `wildcard` for this reason.

-}
recursiveWildcard : Glob (List String)
recursiveWildcard =
    Glob "**"
        (\_ _ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )
        |> map (String.split "/")
        |> map (List.filter (not << String.isEmpty))


{-| -}
zeroOrMore : List String -> Glob (Maybe String)
zeroOrMore matchers =
    Glob
        ("*("
            ++ (matchers |> String.join "|")
            ++ ")"
        )
        (\_ _ captures ->
            case captures of
                first :: rest ->
                    ( if first == "" then
                        Nothing

                      else
                        Just first
                    , rest
                    )

                [] ->
                    ( Just "ERROR", [] )
        )


{-| Match a literal part of a path. Can include `/`s.

Some common uses include

  - The leading part of a pattern, to say "starts with `content/blog/`"
  - The ending part of a pattern, to say "ends with `.md`"
  - In-between wildcards, to say "these dynamic parts are separated by `/`"

```elm
import BackendTask exposing (BackendTask)
import BackendTask.Glob as Glob

blogPosts =
    Glob.succeed
        (\section slug ->
            { section = section, slug = slug }
        )
        |> Glob.match (Glob.literal "content/blog/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal "/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
```

-}
literal : String -> Glob String
literal string =
    Glob string (\_ _ captures -> ( string, captures ))


{-| Adds on to the glob pattern, but does not capture it in the resulting Elm match value. That means this changes which
files will match, but does not change the Elm data type you get for each matching file.

Exactly the same as `capture` except it doesn't capture the matched sub-pattern.

-}
match : Glob a -> Glob value -> Glob value
match (Glob matcherPattern apply1) (Glob pattern apply2) =
    Glob
        (pattern ++ matcherPattern)
        (\fileStats_ fullPath captures ->
            let
                ( _, captured1 ) =
                    -- apply to make sure we drop from the captures list for all capturing patterns
                    -- but don't change the return value
                    captures
                        |> apply1 fileStats_ fullPath

                ( applied2, captured2 ) =
                    captured1
                        |> apply2 fileStats_ fullPath
            in
            ( applied2
            , captured2
            )
        )


{-| Adds on to the glob pattern, and captures it in the resulting Elm match value. That means this both changes which
files will match, and gives you the sub-match as Elm data for each matching file.

Exactly the same as `match` except it also captures the matched sub-pattern.

    type alias ArchivesArticle =
        { year : String
        , month : String
        , day : String
        , slug : String
        }

    archives : BackendTask error ArchivesArticle
    archives =
        Glob.succeed ArchivesArticle
            |> Glob.match (Glob.literal "archive/")
            |> Glob.capture Glob.int
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.int
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.int
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

The file `archive/1977/06/10/apple-2-released.md` will give us this match:

    matches : List error ArchivesArticle
    matches =
        BackendTask.succeed
            [ { year = 1977
              , month = 6
              , day = 10
              , slug = "apple-2-released"
              }
            ]

When possible, it's best to grab data and turn it into structured Elm data when you have it. That way,
you don't end up with duplicate validation logic and data normalization, and your code will be more robust.

If you only care about getting the full matched file paths, you can use `match`. `capture` is very useful because
you can pick apart structured data as you build up your glob pattern. This follows the principle of
[Parse, Don't Validate](https://elm-radio.com/episode/parse-dont-validate/).

-}
capture : Glob a -> Glob (a -> value) -> Glob value
capture (Glob matcherPattern apply1) (Glob pattern apply2) =
    Glob
        (pattern ++ matcherPattern)
        (\fileStats fullPath captures ->
            let
                ( applied1, captured1 ) =
                    captures
                        |> apply1 fileStats fullPath

                ( applied2, captured2 ) =
                    captured1
                        |> apply2 fileStats fullPath
            in
            ( applied1 |> applied2
            , captured2
            )
        )


{-|

    import BackendTask.Glob as Glob

    type Extension
        = Json
        | Yml

    type alias DataFile =
        { name : String
        , extension : String
        }

    dataFiles : BackendTask error (List DataFile)
    dataFiles =
        Glob.succeed DataFile
            |> Glob.match (Glob.literal "my-data/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".")
            |> Glob.capture
                (Glob.oneOf
                    ( ( "yml", Yml )
                    , [ ( "json", Json )
                      ]
                    )
                )

If we have the following files

```shell
- my-data/
    - authors.yml
    - events.json
```

That gives us

    results : BackendTask error (List DataFile)
    results =
        BackendTask.succeed
            [ { name = "authors"
              , extension = Yml
              }
            , { name = "events"
              , extension = Json
              }
            ]

You could also match an optional file path segment using `oneOf`.

    rootFilesMd : BackendTask error (List String)
    rootFilesMd =
        Glob.succeed (\slug -> slug)
            |> Glob.match (Glob.literal "blog/")
            |> Glob.capture Glob.wildcard
            |> Glob.match
                (Glob.oneOf
                    ( ( "", () )
                    , [ ( "/index", () ) ]
                    )
                )
            |> Glob.match (Glob.literal ".md")
            |> Glob.toBackendTask

With these files:

```markdown
- blog/
    - first-post.md
    - second-post/
        - index.md
```

This would give us:

    results : BackendTask error (List String)
    results =
        BackendTask.succeed
            [ "first-post"
            , "second-post"
            ]

-}
oneOf : ( ( String, a ), List ( String, a ) ) -> Glob a
oneOf ( defaultMatch, otherMatchers ) =
    let
        allMatchers : List ( String, a )
        allMatchers =
            defaultMatch :: otherMatchers
    in
    Glob
        ("{"
            ++ (allMatchers |> List.map Tuple.first |> String.join ",")
            ++ "}"
        )
        (\_ _ captures ->
            case captures of
                match_ :: rest ->
                    ( allMatchers
                        |> List.Extra.findMap
                            (\( literalString, result ) ->
                                if literalString == match_ then
                                    Just result

                                else
                                    Nothing
                            )
                        |> Maybe.withDefault (defaultMatch |> Tuple.second)
                    , rest
                    )

                [] ->
                    ( Tuple.second defaultMatch, [] )
        )


{-| -}
atLeastOne : ( ( String, a ), List ( String, a ) ) -> Glob ( a, List a )
atLeastOne ( defaultMatch, otherMatchers ) =
    let
        allMatchers : List ( String, a )
        allMatchers =
            defaultMatch :: otherMatchers
    in
    Glob
        ("+("
            ++ (allMatchers |> List.map Tuple.first |> String.join "|")
            ++ ")"
        )
        (\_ _ captures ->
            case captures of
                match_ :: rest ->
                    ( --( allMatchers
                      --        |> List.Extra.findMap
                      --            (\( literalString, result ) ->
                      --                if literalString == match_ then
                      --                    Just result
                      --
                      --                else
                      --                    Nothing
                      --            )
                      --        |> Maybe.withDefault (defaultMatch |> Tuple.second)
                      --  , []
                      --  )
                      BackendTask.Internal.Glob.extractMatches (defaultMatch |> Tuple.second) allMatchers match_
                        |> toNonEmptyWithDefault (defaultMatch |> Tuple.second)
                    , rest
                    )

                [] ->
                    ( ( Tuple.second defaultMatch, [] ), [] )
        )


toNonEmptyWithDefault : a -> List a -> ( a, List a )
toNonEmptyWithDefault default list =
    case list of
        first :: rest ->
            ( first, rest )

        _ ->
            ( default, [] )


{-| In order to get match data from your glob, turn it into a `BackendTask` with this function.
-}
toBackendTask : Glob a -> BackendTask error (List a)
toBackendTask glob =
    toBackendTaskWithOptions defaultOptions glob


{-| <https://github.com/mrmlnc/fast-glob#onlyfiles>

<https://github.com/mrmlnc/fast-glob#onlydirectories>

-}
type Include
    = OnlyFiles
    | OnlyFolders
    | FilesAndFolders


{-| Custom options you can pass in to run the glob with [`toBackendTaskWithOptions`](#toBackendTaskWithOptions).

    { includeDotFiles = Bool -- https://github.com/mrmlnc/fast-glob#dot
    , include = Include -- return results that are `OnlyFiles`, `OnlyFolders`, or both `FilesAndFolders` (default is `OnlyFiles`)
    , followSymbolicLinks = Bool -- https://github.com/mrmlnc/fast-glob#followsymboliclinks
    , caseSensitiveMatch = Bool -- https://github.com/mrmlnc/fast-glob#casesensitivematch
    , gitignore = Bool -- https://www.npmjs.com/package/globby#gitignore
    , maxDepth = Maybe Int -- https://github.com/mrmlnc/fast-glob#deep
    }

-}
type alias Options =
    { includeDotFiles : Bool -- https://github.com/mrmlnc/fast-glob#dot
    , include : Include
    , followSymbolicLinks : Bool -- https://github.com/mrmlnc/fast-glob#followsymboliclinks
    , caseSensitiveMatch : Bool -- https://github.com/mrmlnc/fast-glob#casesensitivematch
    , gitignore : Bool -- https://www.npmjs.com/package/globby#gitignore
    , maxDepth : Maybe Int -- https://github.com/mrmlnc/fast-glob#deep
    }


{-| The default options used in [`toBackendTask`](#toBackendTask). To use a custom set of options, use [`toBackendTaskWithOptions`](#toBackendTaskWithOptions).
-}
defaultOptions : Options
defaultOptions =
    { includeDotFiles = False
    , followSymbolicLinks = True
    , caseSensitiveMatch = True
    , gitignore = False
    , maxDepth = Nothing
    , include = OnlyFiles
    }


encodeOptions : Options -> Encode.Value
encodeOptions options =
    [ ( "dot", Encode.bool options.includeDotFiles ) |> Just
    , ( "followSymbolicLinks", Encode.bool options.followSymbolicLinks ) |> Just
    , ( "caseSensitiveMatch", Encode.bool options.caseSensitiveMatch ) |> Just
    , ( "gitignore", Encode.bool options.gitignore ) |> Just
    , options.maxDepth |> Maybe.map (\depth -> ( "deep", Encode.int depth ))
    , ( "onlyFiles", options.include == OnlyFiles || options.include == FilesAndFolders |> Encode.bool ) |> Just
    , ( "onlyDirectories", options.include == OnlyFolders || options.include == FilesAndFolders |> Encode.bool ) |> Just
    , ( "stats", Encode.bool True ) |> Just
    ]
        |> List.filterMap identity
        |> Encode.object


{-| Same as toBackendTask, but lets you set custom glob options. For example, to list folders instead of files,

    import BackendTask.Glob as Glob exposing (OnlyFolders, defaultOptions)

    matchingFiles : Glob a -> BackendTask error (List a)
    matchingFiles glob =
        glob
            |> Glob.toBackendTaskWithOptions { defaultOptions | include = OnlyFolders }

-}
toBackendTaskWithOptions : Options -> Glob a -> BackendTask error (List a)
toBackendTaskWithOptions options glob =
    BackendTask.Internal.Request.request
        { name = "glob"
        , body =
            Encode.object
                [ ( "pattern", Encode.string <| BackendTask.Internal.Glob.toPattern glob )
                , ( "options", encodeOptions options )
                ]
                |> BackendTask.Http.jsonBody
        , expect =
            Decode.map3 (\fileStats fullPath captures -> { fileStats = fileStats, fullPath = fullPath, captures = captures })
                (Decode.field "fileStats" (Decode.maybe fileStatsDecoder))
                (Decode.field "fullPath" Decode.string)
                (Decode.field "captures" (Decode.list Decode.string))
                |> Decode.list
                |> Decode.map
                    (\rawGlob ->
                        rawGlob
                            |> List.map
                                (\{ fileStats, fullPath, captures } ->
                                    BackendTask.Internal.Glob.run fileStats fullPath captures glob
                                        |> .match
                                )
                    )
                |> BackendTask.Http.expectJson
        }
        |> BackendTask.onError
            (\_ -> BackendTask.succeed [])


fileStatsDecoder : Decode.Decoder FileStats
fileStatsDecoder =
    Decode.map7 FileStats
        (Decode.field "fullPath" Decode.string)
        (Decode.field "size" Decode.int)
        (Decode.field "mtime" Decode.int |> Decode.map Time.millisToPosix)
        (Decode.field "atime" Decode.int |> Decode.map Time.millisToPosix)
        (Decode.field "ctime" Decode.int |> Decode.map Time.millisToPosix)
        (Decode.field "birthtime" Decode.int |> Decode.map Time.millisToPosix)
        (Decode.field "isDirectory" Decode.bool)


{-| Sometimes you want to make sure there is a unique file matching a particular pattern.
This is a simple helper that will give you a `BackendTask` error if there isn't exactly 1 matching file.
If there is exactly 1, then you successfully get back that single match.

For example, maybe you can have

    import BackendTask exposing (BackendTask)
    import BackendTask.Glob as Glob

    findBlogBySlug : String -> BackendTask FatalError String
    findBlogBySlug slug =
        Glob.succeed identity
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "blog/")
            |> Glob.match (Glob.literal slug)
            |> Glob.match
                (Glob.oneOf
                    ( ( "", () )
                    , [ ( "/index", () ) ]
                    )
                )
            |> Glob.match (Glob.literal ".md")
            |> Glob.expectUniqueMatch
            |> BackendTask.allowFatal

If we used `findBlogBySlug "first-post"` with these files:

```markdown
- blog/
    - first-post/
        - index.md
```

This would give us:

    results : BackendTask FatalError String
    results =
        BackendTask.succeed "blog/first-post/index.md"

If we used `findBlogBySlug "first-post"` with these files:

```markdown
- blog/
    - first-post.md
    - first-post/
        - index.md
```

Then we will get a `BackendTask` error saying `More than one file matched.` Keep in mind that `BackendTask` failures
in build-time routes will cause a build failure, giving you the opportunity to fix the problem before users see the issue,
so it's ideal to make this kind of assertion rather than having fallback behavior that could silently cover up
issues (like if we had instead ignored the case where there are two or more matching blog post files).

-}
expectUniqueMatch :
    Glob a
    -> BackendTask { fatal : FatalError, recoverable : String } a
expectUniqueMatch glob =
    glob
        |> toBackendTask
        |> BackendTask.andThen
            (\matchingFiles ->
                case matchingFiles of
                    [ file ] ->
                        BackendTask.succeed file

                    [] ->
                        BackendTask.fail <|
                            FatalError.recoverable
                                { title = "Non-Unique Glob", body = "No files matched the pattern: " ++ toPatternString glob }
                                ("No files matched the pattern: " ++ toPatternString glob)

                    _ ->
                        BackendTask.fail <|
                            FatalError.recoverable
                                { title = "Non-Unique Glob", body = "Expected a unique match, but more than one file matched." }
                                "More than one file matched."
            )


{-| -}
expectUniqueMatchFromList : List (Glob a) -> BackendTask String a
expectUniqueMatchFromList globs =
    globs
        |> List.map toBackendTask
        |> BackendTask.combine
        |> BackendTask.andThen
            (\matchingFiles ->
                case List.concat matchingFiles of
                    [ file ] ->
                        BackendTask.succeed file

                    [] ->
                        BackendTask.fail <| "No files matched the patterns: " ++ (globs |> List.map toPatternString |> String.join ", ")

                    _ ->
                        BackendTask.fail "More than one file matched."
            )


toPatternString : Glob a -> String
toPatternString glob =
    case glob of
        Glob pattern_ _ ->
            pattern_
