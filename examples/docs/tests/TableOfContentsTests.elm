module TableOfContentsTests exposing (..)

import Expect
import Markdown.Block exposing (..)
import TableOfContents exposing (Entry(..))
import Test exposing (..)


suite : Test
suite =
    describe "table of contents"
        [ test "flat" <|
            \() ->
                TableOfContents.buildToc
                    [ Heading H2 [ Text "Top-Level Item 1" ]
                    , Heading H2 [ Text "Top-Level Item 2" ]
                    , Heading H2 [ Text "Top-Level Item 3" ]
                    ]
                    |> Expect.equal
                        [ Entry { anchorId = "top-level-item-1", level = 2, name = "Top-Level Item 1" } []
                        , Entry { anchorId = "top-level-item-2", level = 2, name = "Top-Level Item 2" } []
                        , Entry { anchorId = "top-level-item-3", level = 2, name = "Top-Level Item 3" } []
                        ]
        , test "nested" <|
            \() ->
                TableOfContents.buildToc
                    [ Heading H2 [ Text "Top-Level Item 1" ]
                    , Heading H3 [ Text "Nested under 1" ]
                    , Heading H2 [ Text "Top-Level Item 3" ]
                    ]
                    |> Expect.equal
                        [ Entry { anchorId = "top-level-item-1", level = 2, name = "Top-Level Item 1" }
                            [ Entry { anchorId = "nested-under-1", level = 3, name = "Nested under 1" } []
                            ]
                        , Entry { anchorId = "top-level-item-3", level = 2, name = "Top-Level Item 3" } []
                        ]
        ]
