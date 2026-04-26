module DocsTests exposing
    ( landingPageTest
    , landingPageHasNavToDocsTest
    , blogIndexListsPostsTest
    , blogPostRendersTest
    , draftPostsHiddenFromIndexTest
    , docsLandingTest
    , docsSectionNavigationTest
    , showcaseLoadsFromAirtableTest
    , navigateLandingToDocsTest
    )

{-| End-to-end tests for the elm-pages docs site.

Demonstrates a content-heavy site backed by glob+frontmatter on a
virtual filesystem, plus an HTTP-backed showcase page.

View in browser: elm-pages dev, then visit /_tests
Run: elm-pages test

-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import TestApp



-- SETUP


{-| Shared baseline: every route mounts Shared.data, which globs
content/docs/\*.md and extracts an H1 from each. We seed one minimal
docs section so Shared.data resolves on every test.
-}
baseSetup : BackendTaskTest.TestSetup
baseSetup =
    BackendTaskTest.init
        |> withDocsSection 1 "what-is-elm-pages" "What is elm-pages?\n\nIntro paragraph."


withDocsSection : Int -> String -> String -> BackendTaskTest.TestSetup -> BackendTaskTest.TestSetup
withDocsSection order slug body setup =
    setup
        |> BackendTaskTest.withFile
            ("content/docs/"
                ++ String.padLeft 2 '0' (String.fromInt order)
                ++ "-"
                ++ slug
                ++ ".md"
            )
            ("# " ++ body)


withBlogPost :
    { slug : String
    , title : String
    , description : String
    , published : String
    , body : String
    }
    -> BackendTaskTest.TestSetup
    -> BackendTaskTest.TestSetup
withBlogPost post setup =
    let
        frontmatter =
            "---\n"
                ++ "{ \"title\": \""
                ++ post.title
                ++ "\", \"description\": \""
                ++ post.description
                ++ "\", \"published\": \""
                ++ post.published
                ++ "\", \"image\": \"some-image\" }\n"
                ++ "---\n\n"
    in
    setup
        |> BackendTaskTest.withFile
            ("content/blog/" ++ post.slug ++ ".md")
            (frontmatter ++ post.body)


withDraftBlogPost :
    { slug : String, title : String, published : String }
    -> BackendTaskTest.TestSetup
    -> BackendTaskTest.TestSetup
withDraftBlogPost post setup =
    let
        frontmatter =
            "---\n"
                ++ "{ \"draft\": true, \"title\": \""
                ++ post.title
                ++ "\", \"description\": \"draft\", \"published\": \""
                ++ post.published
                ++ "\", \"image\": \"x\" }\n"
                ++ "---\n\n"
    in
    setup
        |> BackendTaskTest.withFile
            ("content/blog/" ++ post.slug ++ ".md")
            (frontmatter ++ "# Draft\n\nBody.")


airtableResponse : Encode.Value
airtableResponse =
    Encode.object
        [ ( "records"
          , Encode.list identity
                [ Encode.object
                    [ ( "fields"
                      , Encode.object
                            [ ( "Screenshot URL", Encode.string "https://example.com/shot.png" )
                            , ( "Site Display Name", Encode.string "My Cool Site" )
                            , ( "Live URL", Encode.string "https://cool.example.com" )
                            , ( "Author", Encode.string "Jane Author" )
                            , ( "Author URL", Encode.string "https://jane.example.com" )
                            ]
                      )
                    ]
                ]
          )
        ]



-- TESTS


{-| Trivial: visit the landing page and verify a marquee headline renders.
-}
landingPageTest : TestApp.ProgramTest
landingPageTest =
    TestApp.start "/" baseSetup
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas
            [ Selector.text "Pull in typed Elm data to your pages" ]


{-| The landing page links to the docs. Verifies one of the CTAs is wired up.
-}
landingPageHasNavToDocsTest : TestApp.ProgramTest
landingPageHasNavToDocsTest =
    TestApp.start "/" baseSetup
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas
            [ Selector.tag "a"
            , Selector.containing [ Selector.text "Check out the Docs" ]
            ]


{-| The blog index globs content/blog/\*.md, decodes each frontmatter,
and renders cards. Seed two posts and verify both titles render.
-}
blogIndexListsPostsTest : TestApp.ProgramTest
blogIndexListsPostsTest =
    TestApp.start "/blog"
        (baseSetup
            |> withBlogPost
                { slug = "first-post"
                , title = "Hello, World"
                , description = "First post"
                , published = "2020-01-01"
                , body = "# Hello, World\n\nFirst body."
                }
            |> withBlogPost
                { slug = "second-post"
                , title = "Goodbye, World"
                , description = "Second post"
                , published = "2020-02-01"
                , body = "# Goodbye, World\n\nSecond body."
                }
        )
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas [ Selector.text "Hello, World" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Goodbye, World" ]


{-| Drafts are filtered out of the index. The pre-rendered slug routes
still resolve, but they shouldn't appear in the listing.
-}
draftPostsHiddenFromIndexTest : TestApp.ProgramTest
draftPostsHiddenFromIndexTest =
    TestApp.start "/blog"
        (baseSetup
            |> withBlogPost
                { slug = "published"
                , title = "Published Post"
                , description = "..."
                , published = "2020-01-01"
                , body = "# Published Post\n\nBody."
                }
            |> withDraftBlogPost
                { slug = "draft", title = "Draft Post", published = "2020-02-01" }
        )
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas [ Selector.text "Published Post" ]
        |> PagesProgram.ensureViewHasNot [ Selector.text "Draft Post" ]


{-| Pre-rendered route Blog.Slug\_ reads its file from the virtual FS,
parses frontmatter + markdown body, and renders the post. We seed one
post and visit it directly.
-}
blogPostRendersTest : TestApp.ProgramTest
blogPostRendersTest =
    TestApp.start "/blog/hello-world"
        (baseSetup
            |> withBlogPost
                { slug = "hello-world"
                , title = "Hello, World"
                , description = "First post"
                , published = "2020-01-01"
                , body = "# Hello, World\n\nThis is the body of the post."
                }
        )
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas
            [ Selector.tag "h1", Selector.containing [ Selector.text "Hello, World" ] ]
        |> PagesProgram.ensureViewHas
            [ Selector.text "This is the body of the post." ]


{-| /docs (no section) renders the default "what-is-elm-pages" section.
Exercises Section\_\_'s default-slug fallback.
-}
docsLandingTest : TestApp.ProgramTest
docsLandingTest =
    TestApp.start "/docs" baseSetup
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas
            [ Selector.text "What is elm-pages?" ]


{-| Navigate to a specific docs section by slug.
-}
docsSectionNavigationTest : TestApp.ProgramTest
docsSectionNavigationTest =
    TestApp.start "/docs/getting-started"
        (baseSetup
            |> withDocsSection 2 "getting-started" "Getting Started\n\nHow to start."
        )
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas
            [ Selector.text "Getting Started" ]


{-| Showcase pulls from Airtable. Provide the env var, simulate the GET,
and verify a record renders.
-}
showcaseLoadsFromAirtableTest : TestApp.ProgramTest
showcaseLoadsFromAirtableTest =
    TestApp.start "/showcase"
        (baseSetup
            |> BackendTaskTest.withEnv "AIRTABLE_TOKEN" "test-token"
        )
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.simulateHttpGet
            "https://api.airtable.com/v0/appDykQzbkQJAidjt/elm-pages%20showcase?maxRecords=100&view=Grid%202"
            airtableResponse
        |> PagesProgram.ensureViewHas [ Selector.text "My Cool Site" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Jane Author" ]


{-| End-to-end navigation: land on /, click through to docs, verify content.
-}
navigateLandingToDocsTest : TestApp.ProgramTest
navigateLandingToDocsTest =
    TestApp.start "/" baseSetup
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas
            [ Selector.text "Pull in typed Elm data to your pages" ]
        |> PagesProgram.clickLink "Check out the Docs"
        |> PagesProgram.ensureBrowserUrl
            (\url ->
                if String.contains "/docs" url then
                    Expect.pass

                else
                    Expect.fail ("Expected to be on a /docs URL, got: " ++ url)
            )
        |> PagesProgram.ensureViewHas [ Selector.text "What is elm-pages?" ]
