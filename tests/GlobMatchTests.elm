module GlobMatchTests exposing (suite)

import Expect
import Set
import Test exposing (Test, describe, test)
import Test.GlobMatch as GlobMatch exposing (Token(..))


defaultOptions : GlobMatch.MatchOptions
defaultOptions =
    { caseSensitive = True
    , dot = False
    }


dotOptions : GlobMatch.MatchOptions
dotOptions =
    { caseSensitive = True
    , dot = True
    }


caseInsensitiveOptions : GlobMatch.MatchOptions
caseInsensitiveOptions =
    { caseSensitive = False
    , dot = False
    }


{-| Helper — parse pattern, match single path, return captures or Nothing.
-}
matchOne : String -> String -> Maybe (List String)
matchOne pattern path =
    GlobMatch.matchSinglePath defaultOptions (GlobMatch.parsePattern pattern) path


matchOneDot : String -> String -> Maybe (List String)
matchOneDot pattern path =
    GlobMatch.matchSinglePath dotOptions (GlobMatch.parsePattern pattern) path


matchAll : String -> List String -> List String
matchAll pattern paths =
    GlobMatch.matchPaths defaultOptions (GlobMatch.parsePattern pattern) paths
        |> List.map .fullPath


matchAllDot : String -> List String -> List String
matchAllDot pattern paths =
    GlobMatch.matchPaths dotOptions (GlobMatch.parsePattern pattern) paths
        |> List.map .fullPath


suite : Test
suite =
    describe "GlobMatch"
        [ parsePatternTests
        , literalMatchTests
        , starTests
        , doubleStarTests
        , doubleStarSlashTests
        , braceGroupTests
        , charClassTests
        , parenCaptureTests
        , dotFileTests
        , caseInsensitiveTests
        , captureTests
        , combinedPatternTests
        , directoriesFromFilesTests
        , edgeCaseTests
        ]


parsePatternTests : Test
parsePatternTests =
    describe "parsePattern"
        [ test "literal only" <|
            \() ->
                GlobMatch.parsePattern "content/blog/"
                    |> Expect.equal [ Literal "content/blog/" ]
        , test "star" <|
            \() ->
                GlobMatch.parsePattern "*.md"
                    |> Expect.equal [ Star, Literal ".md" ]
        , test "double star slash" <|
            \() ->
                GlobMatch.parsePattern "**/*.elm"
                    |> Expect.equal [ DoubleStarSlash, Star, Literal ".elm" ]
        , test "double star at end" <|
            \() ->
                GlobMatch.parsePattern "content/**"
                    |> Expect.equal [ Literal "content/", DoubleStar ]
        , test "brace group" <|
            \() ->
                GlobMatch.parsePattern "*.{md,txt}"
                    |> Expect.equal [ Star, Literal ".", BraceGroup [ "md", "txt" ] ]
        , test "complex pattern" <|
            \() ->
                GlobMatch.parsePattern "content/blog/*.md"
                    |> Expect.equal [ Literal "content/blog/", Star, Literal ".md" ]
        , test "double star slash in middle" <|
            \() ->
                GlobMatch.parsePattern "a/**/b/*.elm"
                    |> Expect.equal [ Literal "a/", DoubleStarSlash, Literal "b/", Star, Literal ".elm" ]
        ]


literalMatchTests : Test
literalMatchTests =
    describe "literal matching"
        [ test "exact match" <|
            \() ->
                matchOne "foo.txt" "foo.txt"
                    |> Expect.equal (Just [])
        , test "no match" <|
            \() ->
                matchOne "foo.txt" "bar.txt"
                    |> Expect.equal Nothing
        , test "partial match fails" <|
            \() ->
                matchOne "foo" "foobar"
                    |> Expect.equal Nothing
        , test "pattern longer than path" <|
            \() ->
                matchOne "foobar" "foo"
                    |> Expect.equal Nothing
        ]


starTests : Test
starTests =
    describe "* wildcard"
        [ test "matches filename" <|
            \() ->
                matchOne "*.md" "hello.md"
                    |> Expect.equal (Just [ "hello" ])
        , test "matches in middle" <|
            \() ->
                matchOne "content/*.md" "content/hello.md"
                    |> Expect.equal (Just [ "hello" ])
        , test "does not match across slashes" <|
            \() ->
                matchOne "*.md" "content/hello.md"
                    |> Expect.equal Nothing
        , test "matches empty string" <|
            \() ->
                matchOne "*.md" ".md"
                    |> Expect.equal (Just [ "" ])
        , test "multiple stars" <|
            \() ->
                matchOne "*-*-*.md" "2021-05-27.md"
                    |> Expect.equal (Just [ "2021", "05", "27" ])
        , test "star with literal prefix" <|
            \() ->
                matchOne "slide-*.md" "slide-01.md"
                    |> Expect.equal (Just [ "01" ])
        ]


doubleStarTests : Test
doubleStarTests =
    describe "** (at end)"
        [ test "matches everything recursively" <|
            \() ->
                matchOne "content/**" "content/blog/first-post.md"
                    |> Expect.equal (Just [ "blog/first-post.md" ])
        , test "matches single level" <|
            \() ->
                matchOne "content/**" "content/hello.md"
                    |> Expect.equal (Just [ "hello.md" ])
        , test "matches empty" <|
            \() ->
                matchOne "content/**" "content/"
                    |> Expect.equal (Just [ "" ])
        ]


doubleStarSlashTests : Test
doubleStarSlashTests =
    describe "**/ (zero or more directories)"
        [ test "matches zero directories" <|
            \() ->
                matchOne "**/*.elm" "Main.elm"
                    |> Expect.equal (Just [ "", "Main" ])
        , test "matches one directory" <|
            \() ->
                matchOne "**/*.elm" "src/Main.elm"
                    |> Expect.equal (Just [ "src", "Main" ])
        , test "matches multiple directories" <|
            \() ->
                matchOne "**/*.elm" "src/Ui/Icon.elm"
                    |> Expect.equal (Just [ "src/Ui", "Icon" ])
        , test "with prefix" <|
            \() ->
                matchOne "a/**/*.elm" "a/Main.elm"
                    |> Expect.equal (Just [ "", "Main" ])
        , test "with prefix and subdirs" <|
            \() ->
                matchOne "a/**/*.elm" "a/src/Ui/Icon.elm"
                    |> Expect.equal (Just [ "src/Ui", "Icon" ])
        , test "does not match when prefix is wrong" <|
            \() ->
                matchOne "a/**/*.elm" "b/Main.elm"
                    |> Expect.equal Nothing
        , test "double star slash in middle" <|
            \() ->
                matchOne "a/**/b/*.txt" "a/x/y/b/file.txt"
                    |> Expect.equal (Just [ "x/y", "file" ])
        , test "double star slash in middle matches zero dirs" <|
            \() ->
                matchOne "a/**/b/*.txt" "a/b/file.txt"
                    |> Expect.equal (Just [ "", "file" ])
        ]


braceGroupTests : Test
braceGroupTests =
    describe "{a,b,c} brace groups"
        [ test "matches first alternative" <|
            \() ->
                matchOne "*.{md,txt}" "hello.md"
                    |> Expect.equal (Just [ "hello", "md" ])
        , test "matches second alternative" <|
            \() ->
                matchOne "*.{md,txt}" "hello.txt"
                    |> Expect.equal (Just [ "hello", "txt" ])
        , test "no match" <|
            \() ->
                matchOne "*.{md,txt}" "hello.js"
                    |> Expect.equal Nothing
        , test "empty alternative in brace group" <|
            \() ->
                matchOne "blog/{draft-,}*.md" "blog/my-post.md"
                    |> Expect.equal (Just [ "", "my-post" ])
        , test "non-empty alternative in brace group" <|
            \() ->
                matchOne "blog/{draft-,}*.md" "blog/draft-my-post.md"
                    |> Expect.equal (Just [ "draft-", "my-post" ])
        ]


charClassTests : Test
charClassTests =
    describe "[...] character classes"
        [ test "matches digit" <|
            \() ->
                matchOne "[0-9].txt" "5.txt"
                    |> Expect.equal (Just [ "5" ])
        , test "does not match letter" <|
            \() ->
                matchOne "[0-9].txt" "a.txt"
                    |> Expect.equal Nothing
        , test "matches letter" <|
            \() ->
                matchOne "[a-z].txt" "x.txt"
                    |> Expect.equal (Just [ "x" ])
        ]


parenCaptureTests : Test
parenCaptureTests =
    describe "([0-9]+) capture groups"
        [ test "matches digits" <|
            \() ->
                matchOne "slide-([0-9]+).md" "slide-42.md"
                    |> Expect.equal (Just [ "42" ])
        , test "matches multiple digits" <|
            \() ->
                matchOne "slide-([0-9]+).md" "slide-007.md"
                    |> Expect.equal (Just [ "007" ])
        , test "does not match non-digits" <|
            \() ->
                matchOne "slide-([0-9]+).md" "slide-abc.md"
                    |> Expect.equal Nothing
        , test "does not match empty" <|
            \() ->
                matchOne "slide-([0-9]+).md" "slide-.md"
                    |> Expect.equal Nothing
        ]


dotFileTests : Test
dotFileTests =
    describe "dot file handling"
        [ test "star does not match dot files by default" <|
            \() ->
                matchOne "*.md" ".hidden.md"
                    |> Expect.equal Nothing
        , test "star matches dot files with dot=true" <|
            \() ->
                matchOneDot "*.md" ".hidden.md"
                    |> Expect.equal (Just [ ".hidden" ])
        , test "literal dot prefix still matches" <|
            \() ->
                matchOne ".*.md" ".hidden.md"
                    |> Expect.equal (Just [ "hidden" ])
        , test "dot in middle of name is fine" <|
            \() ->
                matchOne "*.min.js" "app.min.js"
                    |> Expect.equal (Just [ "app" ])
        , test "double star skips dot directories by default" <|
            \() ->
                matchAll "**/*.md" [ "content/.hidden/post.md", "content/blog/post.md" ]
                    |> Expect.equal [ "content/blog/post.md" ]
        , test "double star includes dot directories with dot=true" <|
            \() ->
                matchAllDot "**/*.md" [ "content/.hidden/post.md", "content/blog/post.md" ]
                    |> Expect.equal [ "content/.hidden/post.md", "content/blog/post.md" ]
        ]


caseInsensitiveTests : Test
caseInsensitiveTests =
    describe "case insensitive matching"
        [ test "literal matches case-insensitively" <|
            \() ->
                GlobMatch.matchSinglePath caseInsensitiveOptions
                    (GlobMatch.parsePattern "Content/Blog/*.MD")
                    "content/blog/post.md"
                    |> Expect.notEqual Nothing
        ]


captureTests : Test
captureTests =
    describe "capture extraction"
        [ test "star captures matched text" <|
            \() ->
                matchOne "content/blog/*.md" "content/blog/first-post.md"
                    |> Expect.equal (Just [ "first-post" ])
        , test "multiple captures" <|
            \() ->
                matchOne "blog/*/*.md" "blog/2021/post.md"
                    |> Expect.equal (Just [ "2021", "post" ])
        , test "double star capture" <|
            \() ->
                matchOne "**/*.elm" "src/Ui/Icon.elm"
                    |> Expect.equal (Just [ "src/Ui", "Icon" ])
        , test "brace group capture" <|
            \() ->
                matchOne "*.{yml,json}" "config.json"
                    |> Expect.equal (Just [ "config", "json" ])
        , test "complex pattern captures" <|
            \() ->
                matchOne "content/blog/*-*-*/*.md" "content/blog/2021-05-27/first-post.md"
                    |> Expect.equal (Just [ "2021", "05", "27", "first-post" ])
        ]


combinedPatternTests : Test
combinedPatternTests =
    describe "combined patterns (realistic usage)"
        [ test "blog posts glob" <|
            \() ->
                matchAll "content/blog/*.md"
                    [ "content/blog/first-post.md"
                    , "content/blog/second-post.md"
                    , "content/about.md"
                    , "src/Main.elm"
                    ]
                    |> Expect.equal
                        [ "content/blog/first-post.md"
                        , "content/blog/second-post.md"
                        ]
        , test "recursive elm files" <|
            \() ->
                matchAll "src/**/*.elm"
                    [ "src/Main.elm"
                    , "src/Ui/Button.elm"
                    , "src/Ui/Icon.elm"
                    , "tests/Test.elm"
                    ]
                    |> Expect.equal
                        [ "src/Main.elm"
                        , "src/Ui/Button.elm"
                        , "src/Ui/Icon.elm"
                        ]
        , test "all markdown recursive" <|
            \() ->
                matchAll "**/*.md"
                    [ "README.md"
                    , "content/blog/post.md"
                    , "content/about.md"
                    , "src/Main.elm"
                    ]
                    |> Expect.equal
                        [ "README.md"
                        , "content/blog/post.md"
                        , "content/about.md"
                        ]
        , test "mixed extensions" <|
            \() ->
                matchAll "src/**/*.{elm,js}"
                    [ "src/Main.elm"
                    , "src/index.js"
                    , "src/style.css"
                    , "src/Ui/Button.elm"
                    ]
                    |> Expect.equal
                        [ "src/Main.elm"
                        , "src/index.js"
                        , "src/Ui/Button.elm"
                        ]
        , test "numbered slides" <|
            \() ->
                matchAll "slide-([0-9]+).md"
                    [ "slide-1.md"
                    , "slide-02.md"
                    , "slide-no-match.md"
                    , "slide-.md"
                    ]
                    |> Expect.equal
                        [ "slide-1.md"
                        , "slide-02.md"
                        ]
        ]


directoriesFromFilesTests : Test
directoriesFromFilesTests =
    describe "directoriesFromFiles"
        [ test "extracts all parent directories" <|
            \() ->
                GlobMatch.directoriesFromFiles
                    [ "a/b/c.txt"
                    , "a/d.txt"
                    , "x/y/z/w.txt"
                    ]
                    |> Expect.equal (Set.fromList [ "a", "a/b", "x", "x/y", "x/y/z" ])
        , test "root-level files produce no directories" <|
            \() ->
                GlobMatch.directoriesFromFiles [ "file.txt" ]
                    |> Expect.equal Set.empty
        , test "empty input" <|
            \() ->
                GlobMatch.directoriesFromFiles []
                    |> Expect.equal Set.empty
        ]


edgeCaseTests : Test
edgeCaseTests =
    describe "edge cases"
        [ test "empty pattern matches empty string" <|
            \() ->
                matchOne "" ""
                    |> Expect.equal (Just [])
        , test "empty pattern does not match non-empty" <|
            \() ->
                matchOne "" "foo"
                    |> Expect.equal Nothing
        , test "just star matches filename" <|
            \() ->
                matchOne "*" "foo.txt"
                    |> Expect.equal (Just [ "foo.txt" ])
        , test "just star does not match path" <|
            \() ->
                matchOne "*" "a/b.txt"
                    |> Expect.equal Nothing
        , test "just double star matches anything" <|
            \() ->
                matchOne "**" "a/b/c.txt"
                    |> Expect.equal (Just [ "a/b/c.txt" ])
        , test "trailing slash in pattern" <|
            \() ->
                matchOne "src/" "src/"
                    |> Expect.equal (Just [])
        , test "star at end" <|
            \() ->
                matchOne "content/*" "content/hello"
                    |> Expect.equal (Just [ "hello" ])
        , test "no false positives with partial literal" <|
            \() ->
                matchOne "content/*.md" "contentx/hello.md"
                    |> Expect.equal Nothing
        ]
