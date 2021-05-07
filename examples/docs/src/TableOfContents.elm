module TableOfContents exposing (..)

import Css
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Markdown.Block as Block exposing (Block, HeadingLevel(..), Inline)
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw


type alias TableOfContents data =
    List (Entry data)


type Entry data
    = Entry data (List (Entry data))


addChild : data -> Entry data -> Entry data
addChild childToAdd (Entry parent children) =
    Entry parent (children ++ [ Entry childToAdd [] ])


type alias Data =
    { anchorId : String, name : String, level : Int }


buildToc : List Block -> TableOfContents Data
buildToc blocks =
    let
        headings =
            gatherHeadings blocks
    in
    headings
        |> List.foldl
            (\( currentLevel, styledList ) ( previousLevel, entries ) ->
                let
                    childData =
                        { anchorId = styledToString styledList |> rawTextToId
                        , name = styledToString styledList
                        , level = Block.headingLevelToInt currentLevel
                        }
                in
                case entries of
                    [] ->
                        ( Block.headingLevelToInt currentLevel
                        , Entry childData [] :: entries
                        )

                    latest :: previous ->
                        if previousLevel < Block.headingLevelToInt currentLevel then
                            ( Block.headingLevelToInt currentLevel
                            , (latest |> addChild childData)
                                :: previous
                            )

                        else
                            ( Block.headingLevelToInt currentLevel
                            , Entry childData [] :: entries
                            )
            )
            ( 6, [] )
        |> Tuple.second
        |> List.reverse



--|> Tuple.second


gatherHeadings : List Block -> List ( Block.HeadingLevel, List Inline )
gatherHeadings blocks =
    List.filterMap
        (\block ->
            case block of
                Block.Heading level content ->
                    Just ( level, content )

                _ ->
                    Nothing
        )
        blocks


rawTextToId : String -> String
rawTextToId rawText =
    rawText
        |> String.split " "
        |> String.join "-"
        |> String.toLower


styledToString : List Inline -> String
styledToString inlines =
    --List.map .string list
    --|> String.join "-"
    -- TODO do I need to hyphenate?
    inlines
        |> Block.extractInlineText


surround : List (Html msg) -> Html msg
surround children =
    aside
        [ css
            [ Tw.h_screen
            , Tw.bg_white
            , Tw.flex_shrink_0
            , Tw.w_full
            , Tw.fixed
            , Tw.z_10

            --, Bp.dark
            --    [ Tw.bg_dark
            --    ]
            , Bp.md
                [ Tw.w_64
                , Tw.block
                , Tw.sticky
                ]
            ]
        ]
        [ div
            [ css
                [ Tw.border_gray_200
                , Tw.w_full
                , Tw.p_4
                , Tw.pb_40
                , Tw.h_full
                , Tw.overflow_y_auto

                --, Bp.dark
                --    [ Tw.border_gray_900
                --    ]
                , Bp.md
                    [ Tw.pb_16
                    ]
                ]
            ]
            children
        ]


view : Maybe String -> TableOfContents Data -> Html msg
view current toc =
    surround
        [ ul
            []
            (toc
                |> List.map (level1Entry current)
            )
        ]


level1Entry : Maybe String -> Entry Data -> Html msg
level1Entry current (Entry data children) =
    let
        isCurrent =
            current == Just data.anchorId
    in
    li
        [ css
            [ Tw.space_y_3
            , Tw.font_semibold
            , Tw.text_gray_900
            , Tw.rounded_lg
            ]
        ]
        [ item isCurrent ("/docs/" ++ data.anchorId) data.name
        , ul
            [ css
                [ Tw.space_y_3
                ]
            ]
            (children
                |> List.map (level2Entry data.anchorId)
            )
        ]


item : Bool -> String -> String -> Html msg
item isCurrent href body =
    a
        [ Attr.href href
        , css
            [ Tw.block
            , Tw.w_full
            , Tw.text_left
            , Tw.text_base
            , Tw.no_underline
            , Tw.mt_1
            , Tw.p_2
            , Tw.rounded
            , Tw.select_none
            , Tw.outline_none
            , if isCurrent then
                Css.batch
                    [ Tw.bg_gray_200
                    ]

              else
                Css.batch
                    [ Css.hover
                        [ Tw.text_black
                        , Tw.bg_gray_100
                        ]
                    , Tw.text_gray_500
                    ]
            ]
        ]
        [ text body ]


level2Entry : String -> Entry Data -> Html msg
level2Entry parentPath (Entry data children) =
    li
        [ css
            [ Tw.ml_4
            ]
        ]
        [ item False ("/docs/" ++ parentPath ++ "#" ++ data.anchorId) data.name
        ]
