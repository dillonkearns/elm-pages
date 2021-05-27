module DataSource.Glob exposing
    ( capture, match
    , fullFilePath, captureFilePath
    , wildcard, recursiveWildcard, int
    , expectUniqueFile
    , Glob, atLeastOne, extractMatches, literal, map, oneOf, run, singleFile, succeed, toNonEmptyWithDefault, toPattern, toDataSource, zeroOrMore
    )

{-| This module helps you get a List of matching file paths from your local file system as a `DataSource`. See the `DataSource` module documentation
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

There are two functions for building up a Glob pattern. `capture` and `match`.

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
and error prone. That's what the `fullFilePath` helper is for.


## Reading matching files

@docs fullFilePath, captureFilePath

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


## File Matching Helpers

@docs expectUniqueFile

@docs Glob, atLeastOne, extractMatches, literal, map, oneOf, run, singleFile, succeed, toNonEmptyWithDefault, toPattern, toDataSource, zeroOrMore

-}

import DataSource
import DataSource.Http
import List.Extra
import OptimizedDecoder
import Regex
import Secrets


{-| -}
type Glob a
    = Glob String String (String -> List String -> ( a, List String ))


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


{-| -}
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


{-| -}
run : String -> Glob a -> { match : a, pattern : String }
run rawInput (Glob pattern regex applyCapture) =
    let
        fullRegex =
            "^" ++ regex ++ "$"

        regexCaptures : List String
        regexCaptures =
            Regex.find parsedRegex rawInput
                |> List.concatMap .submatches
                |> List.map (Maybe.withDefault "")

        parsedRegex =
            Regex.fromString fullRegex |> Maybe.withDefault Regex.never
    in
    { match =
        regexCaptures
            |> List.reverse
            |> applyCapture rawInput
            |> Tuple.first
    , pattern = pattern
    }


{-| -}
toPattern : Glob a -> String
toPattern (Glob pattern regex applyCapture) =
    pattern


{-| -}
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


{-| -}
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


{-| -}
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
                      extractMatches (defaultMatch |> Tuple.second) allMatchers match_
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


{-| -}
extractMatches : a -> List ( String, a ) -> String -> List a
extractMatches defaultValue list string =
    if string == "" then
        []

    else
        let
            ( matchedValue, updatedString ) =
                List.Extra.findMap
                    (\( literalString, value ) ->
                        if string |> String.startsWith literalString then
                            Just ( value, string |> String.dropLeft (String.length literalString) )

                        else
                            Nothing
                    )
                    list
                    |> Maybe.withDefault ( defaultValue, "" )
        in
        matchedValue
            :: extractMatches defaultValue list updatedString


{-| -}
toDataSource : Glob a -> DataSource.DataSource (List a)
toDataSource glob =
    DataSource.Http.get (Secrets.succeed <| "glob://" ++ toPattern glob)
        (OptimizedDecoder.string
            |> OptimizedDecoder.list
            |> OptimizedDecoder.map
                (\rawGlob -> rawGlob |> List.map (\matchedPath -> run matchedPath glob |> .match))
        )


{-| -}
singleFile : String -> DataSource.DataSource (Maybe String)
singleFile filePath =
    succeed identity
        |> match (literal filePath)
        |> capture fullFilePath
        |> toDataSource
        |> DataSource.andThen
            (\globResults ->
                case globResults of
                    [] ->
                        DataSource.succeed Nothing

                    [ single ] ->
                        Just single |> DataSource.succeed

                    multipleResults ->
                        DataSource.fail <| "Unexpected - getSingleFile returned multiple results." ++ (multipleResults |> String.join ", ")
            )


{-| -}
expectUniqueFile : Glob a -> DataSource.DataSource String
expectUniqueFile glob =
    succeed identity
        |> match glob
        |> capture fullFilePath
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
