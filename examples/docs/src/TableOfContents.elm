module TableOfContents exposing (..)

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


view : TableOfContents Data -> Html msg
view toc =
    div
        [ css
            [ Tw.bg_gray_50
            , Tw.neg_mx_4
            , Tw.py_12
            , Tw.px_4
            , Bp.lg
                [ Tw.bg_transparent
                , Tw.mx_0
                , Tw.pl_0
                , Tw.pr_8
                ]
            , Bp.sm
                [ Tw.neg_mx_6
                , Tw.py_16
                , Tw.px_6
                ]
            ]
        ]
        [ div
            [ css
                [ Tw.text_sm

                --, Tw.max_w_[37_dot_5rem]
                , Tw.mx_auto
                , Tw.relative
                , Bp.lg
                    [ Tw.max_w_none
                    , Tw.mx_0
                    , Tw.sticky
                    , Tw.top_10
                    ]
                ]
            , Attr.attribute "x-data" "TableOfContents()"
            , Attr.attribute "x-init" "init()"
            ]
            (ul
                [ css
                    [ Tw.space_y_8
                    , Tw.border_l
                    , Tw.border_gray_200
                    , Tw.pl_6
                    ]
                ]
                (toc
                    |> List.map level1Entry
                )
                :: [ div
                        [ css
                            [ Tw.absolute
                            , Tw.top_0
                            , Tw.left_0
                            , Tw.w_px
                            , Tw.bg_blue_500
                            , Tw.origin_top
                            , Tw.transition_transform
                            , Tw.duration_300
                            ]
                        , Attr.attribute ":style" "'height:'+(height?'1px':'0')+';transform:translateY('+top+'px) scaleY('+height+')'"
                        , Attr.attribute ":class" "initialized ? 'transition-transform duration-300' : ''"
                        , Attr.style "height" "1px"
                        , Attr.style "transform" "translateY(148px) scaleY(20)"
                        ]
                        []
                   ]
            )
        ]


level1Entry : Entry Data -> Html msg
level1Entry (Entry data children) =
    li
        [ css
            [ Tw.space_y_3
            ]
        ]
        [ a
            [ Attr.href <| "/docs#" ++ data.anchorId
            , css
                [ Tw.block
                , Tw.font_extrabold
                , Tw.transition_colors
                , Tw.duration_300
                , Tw.text_gray_900
                ]
            , Attr.attribute ":class" "{ 'transition-colors duration-300': initialized, 'text-teal-600': activeSlug === 'getting-set-up', 'text-gray-900': activeSlug !== 'getting-set-up' }"
            ]
            [ text data.name ]
        , ul
            [ css
                [ Tw.space_y_3
                ]
            ]
            (children
                |> List.map level2Entry
            )
        ]


level2Entry : Entry Data -> Html msg
level2Entry (Entry data children) =
    li
        [ css
            [ Tw.ml_4
            ]
        ]
        [ a
            [ Attr.href <| "/docs#" ++ data.anchorId
            , css
                [ Tw.block
                , Tw.transition_colors
                , Tw.duration_300
                ]
            , Attr.attribute ":class" "{ 'transition-colors duration-300': initialized, 'text-teal-600': activeSlug === 'requirements' }"
            ]
            [ text data.name ]
        ]
