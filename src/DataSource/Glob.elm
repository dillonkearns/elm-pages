module DataSource.Glob exposing
    ( Glob
    , capture, match
    , captureFilePath
    , wildcard, recursiveWildcard, int
    , expectUniqueMatch
    , literal
    , atLeastOne, map, oneOf, succeed, toDataSource, zeroOrMore
    , toNonEmptyWithDefault
    )

{-|

@docs Glob

This module helps you get a List of matching file paths from your local file system as a `DataSource`. See the `DataSource` module documentation
for ways you can combine and map `DataSource`s.

A common example would be to find all the markdown files of your blog posts. If you have all your blog posts in `content/blog/*.md`
, then you could use that glob pattern in most shells to refer to each of those files.

With the `DataSource.Glob` API, you could get all of those files like so:

    import DataSource exposing (DataSource)

    blogPostsGlob : DataSource (List String)
    blogPostsGlob =
        Glob.succeed (\slug -> slug)
            |> Glob.match (Glob.literal "content/blog/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".md")
            |> Glob.toDataSource

Let's say you have these files locally:

```shell
- elm.json
- src/
- content/
  - blog/
    - first-post.md
    - second-post.md
```

We would end up with a `DataSource` like this:

    DataSource.succeed [ "first-post", "second-post" ]

Of course, if you add or remove matching files, the DataSource will get those new files (unlike `DataSource.succeed`). That's why we have Glob!

You can even see the `elm-pages dev` server will automatically flow through any added/removed matching files with its hot module reloading.

But why did we get `"first-post"` instead of a full file path, like `"content/blog/first-post.md"`? That's the difference between
`capture` and `match`.


## Capture and Match

There are two functions for building up a Glob pattern: `capture` and `match`.

Whether you use `capture` or `match`, the actual file paths that match the glob you build will not change. It's only the resulting
Elm value you get from each matching file that will depend on `capture` or `match`.

@docs capture, match

`capture` is a lot like building up a JSON decoder with a pipeline.

Let's try our blogPostsGlob from before, but change every `match` to `capture`.

    import DataSource exposing (DataSource)

    blogPostsGlob :
        DataSource
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
            |> Glob.toDataSource

Notice that we now need 3 arguments at the start of our pipeline instead of 1. That's because
we apply 1 more argument every time we do a `Glob.capture`, much like `Json.Decode.Pipeline.required`, or other pipeline APIs.

Now we actually have the full file path of our files. But having that slug (like `first-post`) is also very helpful sometimes, so
we kept that in our record as well. So we'll now have the equivalent of this `DataSource` with the current `.md` files in our `blog` folder:

    DataSource.succeed
        [ { filePath = "content/blog/first-post.md"
          , slug = "first-post"
          }
        , { filePath = "content/blog/second-post.md"
          , slug = "second-post"
          }
        ]

Having the full file path lets us read in files. But concatenating it manually is tedious
and error prone. That's what the `captureFilePath` helper is for.


## Reading matching files

@docs captureFilePath

    import DataSource exposing (DataSource)

    blogPosts :
        DataSource
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
            |> Glob.toDataSource

In many cases you will want to use a `Glob` `DataSource`, and then read the body or frontmatter from matching files.


## Reading Metadata for each Glob Match

For example, if we had files like this:

```markdown
---
title: My First Post
---
This is my first post!
```

Then we could read that title for our blog post list page using our `blogPosts` `DataSource` that we defined above.

    import DataSource.File
    import OptimizedDecoder as Decode exposing (Decoder)

    titles : DataSource (List BlogPost)
    titles =
        blogPosts
            |> DataSource.map
                (List.map
                    (\blogPost ->
                        DataSource.File.request
                            blogPost.filePath
                            (DataSource.File.frontmatter blogFrontmatterDecoder)
                    )
                )
            |> DataSource.resolve

    type alias BlogPost =
        { title : String }

    blogFrontmatterDecoder : Decoder BlogPost
    blogFrontmatterDecoder =
        Decode.map BlogPost
            (Decode.field "title" Decode.string)

That will give us

    DataSource.succeed
        [ { title = "My First Post" }
        , { title = "My Second Post" }
        ]


## Capturing Patterns

@docs wildcard, recursiveWildcard, int


## Matching a Specific Number of Files

@docs expectUniqueMatch


## Glob Patterns

@docs literal

@docs atLeastOne, map, oneOf, succeed, toDataSource, zeroOrMore


## Is this useful/used?

@docs toNonEmptyWithDefault

-}

import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.Internal.Glob exposing (Glob(..))
import List.Extra
import OptimizedDecoder
import Regex
import Secrets


{-| -}
type alias Glob a =
    DataSource.Internal.Glob.Glob a


{-| -}
map : (a -> b) -> Glob a -> Glob b
map mapFn (Glob pattern regex applyCapture) =
    Glob pattern
        regex
        (\fullPath captures ->
            captures
                |> applyCapture fullPath
                |> Tuple.mapFirst mapFn
        )


{-| -}
succeed : constructor -> Glob constructor
succeed constructor =
    Glob "" "" (\_ captures -> ( constructor, captures ))


{-| -}
fullFilePath : Glob String
fullFilePath =
    Glob ""
        ""
        (\fullPath captures ->
            ( fullPath, captures )
        )


{-| -}
captureFilePath : Glob (String -> value) -> Glob value
captureFilePath =
    capture fullFilePath


{-| -}
wildcard : Glob String
wildcard =
    Glob "*"
        wildcardRegex
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


wildcardRegex : String
wildcardRegex =
    "([^/]*?)"


{-| -}
int : Glob Int
int =
    Glob "[0-9]+"
        "([0-9]+?)"
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( String.toInt first |> Maybe.withDefault -1, rest )

                [] ->
                    ( -1, [] )
        )


{-| Matches any number of characters, including `/`, as long as it's the only thing in a path part.

In contrast, `wildcard` will never match `/`, so it only matches within a single path part.

This is the elm-pages equivalent of `**/*.txt` in standard shell syntax:

    example =
        Glob.succeed Tuple.pair
            |> Glob.match (Glob.literal "articles/")
            |> Glob.capture Glob.recursiveWildcard
            |> Glob.match (Glob.literal "/")
            |> Glob.capture Glob.wildcard
            |> Glob.match (Glob.literal ".txt")

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

    matches : DataSource (List ( List String, String ))
    matches =
        DataSource.succeed
            [ ( [ "archive", "1977", "06", "10" ], "apple-2-announced" )
            , ( [], "google-io-2021-recap" )
            ]

Note that the recursive wildcard conveniently gives us a `List String`, where
each String is a path part with no slashes (like `archive`).

And also note that it matches 0 path parts into an empty list.

If we didn't include the `wildcard` after the `recursiveWildcard`, then we would only get
a single level of matches because it is followed by a file extension.

    example : DataSource (List String)
    example =
        Glob.succeed identity
            |> Glob.match (Glob.literal "articles/")
            |> Glob.capture Glob.recursiveWildcard
            |> Glob.match (Glob.literal ".txt")

    matches : DataSource (List String)
    matches =
        DataSource.succeed
            [ "google-io-2021-recap"
            ]

This is usually not what is intended. Using `recursiveWildcard` is usually followed by a `wildcard` for this reason.

-}
recursiveWildcard : Glob (List String)
recursiveWildcard =
    Glob "**"
        recursiveWildcardRegex
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )
        |> map (String.split "/")
        |> map (List.filter (not << String.isEmpty))


recursiveWildcardRegex : String
recursiveWildcardRegex =
    "(.*?)"


{-| -}
zeroOrMore : List String -> Glob (Maybe String)
zeroOrMore matchers =
    Glob
        ("*("
            ++ (matchers |> String.join "|")
            ++ ")"
        )
        ("((?:"
            ++ (matchers |> List.map regexEscaped |> String.join "|")
            ++ ")*)"
        )
        (\_ captures ->
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


{-| -}
literal : String -> Glob String
literal string =
    Glob string (regexEscaped string) (\_ captures -> ( string, captures ))


regexEscaped : String -> String
regexEscaped stringLiteral =
    --https://stackoverflow.com/a/6969486
    stringLiteral
        |> Regex.replace regexEscapePattern (\match_ -> "\\" ++ match_.match)


regexEscapePattern : Regex.Regex
regexEscapePattern =
    "[.*+?^${}()|[\\]\\\\]"
        |> Regex.fromString
        |> Maybe.withDefault Regex.never


{-| Adds on to the glob pattern, but does not capture it in the resulting Elm match value. That means this changes which
files will match, but does not change the Elm data type you get for each matching file.

Exactly the same as `capture` except it doesn't capture the matched sub-pattern.

-}
match : Glob a -> Glob value -> Glob value
match (Glob matcherPattern regex1 apply1) (Glob pattern regex2 apply2) =
    Glob
        (pattern ++ matcherPattern)
        (combineRegexes regex1 regex2)
        (\fullPath captures ->
            let
                ( _, captured1 ) =
                    -- apply to make sure we drop from the captures list for all capturing patterns
                    -- but don't change the return value
                    captures
                        |> apply1 fullPath

                ( applied2, captured2 ) =
                    captured1
                        |> apply2 fullPath
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

    archives : DataSource ArchivesArticle
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
            |> expectAll

The file `archive/1977/06/10/apple-2-released.md` will give us this match:

    matches : List ArchivesArticle
    matches =
        DataSource.succeed
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
capture (Glob matcherPattern regex1 apply1) (Glob pattern regex2 apply2) =
    Glob
        (pattern ++ matcherPattern)
        (combineRegexes regex1 regex2)
        (\fullPath captures ->
            let
                ( applied1, captured1 ) =
                    captures
                        |> apply1 fullPath

                ( applied2, captured2 ) =
                    captured1
                        |> apply2 fullPath
            in
            ( applied1 |> applied2
            , captured2
            )
        )


combineRegexes : String -> String -> String
combineRegexes regex1 regex2 =
    if isRecursiveWildcardSlashWildcard regex1 regex2 then
        (regex2 |> String.dropRight 1) ++ regex1

    else
        regex2 ++ regex1


isRecursiveWildcardSlashWildcard : String -> String -> Bool
isRecursiveWildcardSlashWildcard regex1 regex2 =
    (regex2 |> String.endsWith (recursiveWildcardRegex ++ "/"))
        && (regex1 |> String.startsWith wildcardRegex)


{-|

    import DataSource.Glob as Glob

    type Extension
        = Json
        | Yml

    type alias DataFile =
        { name : String
        , extension : String
        }

    dataFiles : DataSource (List DataFile)
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

    results : DataSource (List DataFile)
    results =
        DataSource.succeed
            [ { name = "authors"
              , extension = Yml
              }
            , { name = "events"
              , extension = Json
              }
            ]

You could also match an optional file path segment using `oneOf`.

    rootFilesMd : DataSource (List String)
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
            |> Glob.toDataSource

With these files:

```markdown
- blog/
    - first-post.md
    - second-post/
        - index.md
```

This would give us:

    results : DataSource (List String)
    results =
        DataSource.succeed
            [ "first-post"
            , "second-post"
            ]

-}
oneOf : ( ( String, a ), List ( String, a ) ) -> Glob a
oneOf ( defaultMatch, otherMatchers ) =
    let
        allMatchers =
            defaultMatch :: otherMatchers
    in
    Glob
        ("{"
            ++ (allMatchers |> List.map Tuple.first |> String.join ",")
            ++ "}"
        )
        ("("
            ++ String.join "|"
                ((allMatchers |> List.map Tuple.first |> List.map regexEscaped)
                    |> List.map regexEscaped
                )
            ++ ")"
        )
        (\_ captures ->
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
        allMatchers =
            defaultMatch :: otherMatchers
    in
    Glob
        ("+("
            ++ (allMatchers |> List.map Tuple.first |> String.join "|")
            ++ ")"
        )
        ("((?:"
            ++ (allMatchers |> List.map Tuple.first |> List.map regexEscaped |> String.join "|")
            ++ ")+)"
        )
        (\_ captures ->
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
                      DataSource.Internal.Glob.extractMatches (defaultMatch |> Tuple.second) allMatchers match_
                        |> toNonEmptyWithDefault (defaultMatch |> Tuple.second)
                    , rest
                    )

                [] ->
                    ( ( Tuple.second defaultMatch, [] ), [] )
        )


{-| -}
toNonEmptyWithDefault : a -> List a -> ( a, List a )
toNonEmptyWithDefault default list =
    case list of
        first :: rest ->
            ( first, rest )

        _ ->
            ( default, [] )


{-| In order to get match data from your glob, turn it into a `DataSource` with this function.
-}
toDataSource : Glob a -> DataSource.DataSource (List a)
toDataSource glob =
    DataSource.Http.get (Secrets.succeed <| "glob://" ++ DataSource.Internal.Glob.toPattern glob)
        (OptimizedDecoder.string
            |> OptimizedDecoder.list
            |> OptimizedDecoder.map
                (\rawGlob -> rawGlob |> List.map (\matchedPath -> DataSource.Internal.Glob.run matchedPath glob |> .match))
        )


{-| Sometimes you want to make sure there is a unique file matching a particular pattern.
This is a simple helper that will give you a `DataSource` error if there isn't exactly 1 matching file.
If there is exactly 1, then you successfully get back that single match.

For example, maybe you can have

    import DataSource exposing (DataSource)
    import DataSource.Glob as Glob

    findBlogBySlug : String -> DataSource String
    findBlogBySlug slug =
        Glob.succeed identity
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "blog/")
            |> Glob.capture (Glob.literal slug)
            |> Glob.match
                (Glob.oneOf
                    ( ( "", () )
                    , [ ( "/index", () ) ]
                    )
                )
            |> Glob.match (Glob.literal ".md")
            |> Glob.expectUniqueMatch

If we used `findBlogBySlug "first-post"` with these files:

```markdown
- blog/
    - first-post/
        - index.md
```

This would give us:

    results : DataSource String
    results =
        DataSource.succeed "blog/first-post/index.md"

If we used `findBlogBySlug "first-post"` with these files:

```markdown
- blog/
    - first-post.md
    - first-post/
        - index.md
```

Then we will get a `DataSource` error saying `More than one file matched.` Keep in mind that `DataSource` failures
in build-time routes will cause a build failure, giving you the opportunity to fix the problem before users see the issue,
so it's ideal to make this kind of assertion rather than having fallback behavior that could silently cover up
issues (like if we had instead ignored the case where there are two or more matching blog post files).

-}
expectUniqueMatch : Glob a -> DataSource a
expectUniqueMatch glob =
    glob
        |> toDataSource
        |> DataSource.andThen
            (\matchingFiles ->
                case matchingFiles of
                    [ file ] ->
                        DataSource.succeed file

                    [] ->
                        DataSource.fail "No files matched."

                    _ ->
                        DataSource.fail "More than one file matched."
            )
