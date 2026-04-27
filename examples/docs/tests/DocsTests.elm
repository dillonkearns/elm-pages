module DocsTests exposing (suite, landingPageSnapshots)

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



-- SUITE


suite : PagesProgram.Test
suite =
    PagesProgram.describe "elm-pages docs site"
        [ PagesProgram.describe "Landing page"
            [ PagesProgram.test "renders the marquee headline"
                landingPageStart
                landingPageSteps
            , PagesProgram.test "links to the docs"
                (TestApp.start "/" baseSetup)
                [ PagesProgram.ensureViewHas
                    [ Selector.tag "a"
                    , Selector.containing [ Selector.text "Check out the Docs" ]
                    ]
                ]
            , PagesProgram.test "navigates from landing to docs"
                (TestApp.start "/" baseSetup)
                [ PagesProgram.ensureViewHas
                    [ Selector.text "Pull in typed Elm data to your pages" ]
                , PagesProgram.clickLink "Check out the Docs"
                , PagesProgram.ensureBrowserUrl
                    (\url ->
                        if String.contains "/docs" url then
                            Expect.pass

                        else
                            Expect.fail ("Expected to be on a /docs URL, got: " ++ url)
                    )
                , PagesProgram.ensureViewHas [ Selector.text "What is elm-pages?" ]
                ]
            ]
        , PagesProgram.describe "Blog"
            [ PagesProgram.test "lists published posts"
                (TestApp.start "/blog"
                    (baseSetup
                        |> withBlogPost
                            { slug = "first-post"
                            , title = "Hello, World"
                            , description = "First post"
                            , published = "2020-01-01"
                            , body = """# Hello, World

First body.
"""
                            }
                        |> withBlogPost
                            { slug = "second-post"
                            , title = "Goodbye, World"
                            , description = "Second post"
                            , published = "2020-02-01"
                            , body = """# Goodbye, World

Second body.
"""
                            }
                    )
                )
                [ PagesProgram.ensureViewHas [ Selector.text "Hello, World" ]
                , PagesProgram.ensureViewHas [ Selector.text "Goodbye, World" ]
                ]
            , PagesProgram.test "renders a post page"
                (TestApp.start "/blog/hello-world"
                    (baseSetup
                        |> withBlogPost
                            { slug = "hello-world"
                            , title = "Hello, World"
                            , description = "First post"
                            , published = "2020-01-01"
                            , body = """# Hello, World

This is the body of the post.
"""
                            }
                    )
                )
                [ PagesProgram.ensureViewHas
                    [ Selector.tag "h1", Selector.containing [ Selector.text "Hello, World" ] ]
                , PagesProgram.ensureViewHas
                    [ Selector.text "This is the body of the post." ]
                ]
            , PagesProgram.test "hides drafts from the index"
                (TestApp.start "/blog"
                    (baseSetup
                        |> withBlogPost
                            { slug = "published"
                            , title = "Published Post"
                            , description = "..."
                            , published = "2020-01-01"
                            , body = """# Published Post

Body.
"""
                            }
                        |> withDraftBlogPost
                            { slug = "draft", title = "Draft Post", published = "2020-02-01" }
                    )
                )
                [ PagesProgram.ensureViewHas [ Selector.text "Published Post" ]
                , PagesProgram.ensureViewHasNot [ Selector.text "Draft Post" ]
                ]
            ]
        , PagesProgram.describe "Docs"
            [ PagesProgram.test "default section renders at /docs"
                (TestApp.start "/docs" baseSetup)
                [ PagesProgram.ensureViewHas [ Selector.text "What is elm-pages?" ] ]
            , PagesProgram.test "navigates to a specific section"
                (TestApp.start "/docs/getting-started"
                    (baseSetup
                        |> withDocsSection 2
                            "getting-started"
                            """# Getting Started

How to start.
"""
                    )
                )
                [ PagesProgram.ensureViewHas [ Selector.text "Getting Started" ] ]
            ]
        , PagesProgram.describe "Showcase"
            [ PagesProgram.test "loads records from Airtable"
                (TestApp.start "/showcase"
                    (baseSetup
                        |> BackendTaskTest.withEnv "AIRTABLE_TOKEN" "test-token"
                    )
                )
                [ PagesProgram.simulateHttpGet
                    "https://api.airtable.com/v0/appDykQzbkQJAidjt/elm-pages%20showcase?maxRecords=100&view=Grid%202"
                    airtableResponse
                , PagesProgram.ensureViewHas [ Selector.text "My Cool Site" ]
                , PagesProgram.ensureViewHas [ Selector.text "Jane Author" ]
                ]
            ]
        ]



-- MODEL INSPECTOR HOOK


landingPageStart : TestApp.ProgramTest
landingPageStart =
    TestApp.start "/" baseSetup


landingPageSteps =
    [ PagesProgram.ensureViewHas
        [ Selector.text "Pull in typed Elm data to your pages" ]
    ]


{-| Snapshot stream for the landing page test, used by
[`DocsModelInspectorTest`](DocsModelInspectorTest) to assert that the
visual runner's model inspector doesn't leak harness internals.
-}
landingPageSnapshots : List PagesProgram.Snapshot
landingPageSnapshots =
    PagesProgram.snapshots landingPageStart landingPageSteps



-- SETUP


{-| Shared baseline: every route mounts Shared.data, which globs
content/docs/\*.md and extracts an H1 from each. We seed one minimal
docs section so Shared.data resolves on every test.
-}
baseSetup : BackendTaskTest.TestSetup
baseSetup =
    BackendTaskTest.init
        |> withDocsSection 1
            "what-is-elm-pages"
            """# What is elm-pages?

Intro paragraph.
"""


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
            body


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
    setup
        |> BackendTaskTest.withFile
            ("content/blog/" ++ post.slug ++ ".md")
            (frontmatterBlock
                [ ( "title", post.title )
                , ( "description", post.description )
                , ( "published", post.published )
                , ( "image", "some-image" )
                ]
                ++ post.body
            )


withDraftBlogPost :
    { slug : String, title : String, published : String }
    -> BackendTaskTest.TestSetup
    -> BackendTaskTest.TestSetup
withDraftBlogPost post setup =
    setup
        |> BackendTaskTest.withFile
            ("content/blog/" ++ post.slug ++ ".md")
            (frontmatterBlockWith
                [ ( "draft", Encode.bool True )
                , ( "title", Encode.string post.title )
                , ( "description", Encode.string "draft" )
                , ( "published", Encode.string post.published )
                , ( "image", Encode.string "x" )
                ]
                ++ """# Draft

Body.
"""
            )


frontmatterBlock : List ( String, String ) -> String
frontmatterBlock fields =
    frontmatterBlockWith (List.map (\( k, v ) -> ( k, Encode.string v )) fields)


frontmatterBlockWith : List ( String, Encode.Value ) -> String
frontmatterBlockWith fields =
    """---
""" ++ Encode.encode 2 (Encode.object fields) ++ """
---

"""


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
