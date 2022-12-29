module TableOfContents exposing (..)

import Css
import DataSource exposing (DataSource)
import DataSource.File
import Exception exposing (Throwable)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import List.Extra
import Markdown.Block as Block exposing (Block, Inline)
import Markdown.Parser
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw


dataSource :
    DataSource Throwable (List { file | filePath : String, slug : String })
    -> DataSource Throwable (TableOfContents Data)
dataSource docFiles =
    docFiles
        |> DataSource.map
            (\sections ->
                sections
                    |> List.map
                        (\section ->
                            DataSource.File.bodyWithoutFrontmatter
                                section.filePath
                                |> DataSource.throw
                                |> DataSource.andThen (headingsDecoder section.slug)
                        )
            )
        |> DataSource.resolve


headingsDecoder : String -> String -> DataSource Throwable (Entry Data)
headingsDecoder slug rawBody =
    rawBody
        |> Markdown.Parser.parse
        |> Result.mapError (\_ -> Exception.fromString "Markdown parsing error")
        |> Result.map gatherHeadings
        |> Result.andThen (nameAndTopLevel slug >> Result.mapError Exception.fromString)
        |> DataSource.fromResult


nameAndTopLevel :
    String
    -> List ( Block.HeadingLevel, List Block.Inline )
    -> Result String (Entry Data)
nameAndTopLevel slug headings =
    let
        h1 : Maybe (List Block.Inline)
        h1 =
            List.Extra.findMap
                (\( level, inlines ) ->
                    case level of
                        Block.H1 ->
                            Just inlines

                        _ ->
                            Nothing
                )
                headings

        h2s : List (List Block.Inline)
        h2s =
            List.filterMap
                (\( level, inlines ) ->
                    case level of
                        Block.H2 ->
                            Just inlines

                        _ ->
                            Nothing
                )
                headings
    in
    case h1 of
        Just justH1 ->
            Ok
                (Entry
                    { anchorId = slug
                    , name = styledToString justH1
                    , level = 1
                    }
                    (h2s
                        |> List.map (toData 2)
                        |> List.map (\l2Data -> Entry l2Data [])
                    )
                )

        _ ->
            Err ""


toData : Int -> List Block.Inline -> { anchorId : String, name : String, level : Int }
toData level styledList =
    { anchorId = styledToString styledList |> rawTextToId
    , name = styledToString styledList
    , level = level
    }


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


surround : Bool -> Bool -> List (Html msg) -> Html msg
surround showMobileMenu onDocsPage children =
    aside
        [ css
            [ Tw.h_screen
            , Tw.bg_white
            , Tw.flex_shrink_0
            , Tw.top_0
            , Tw.pt_16
            , Tw.w_full
            , if showMobileMenu then
                Tw.block

              else
                Tw.hidden
            , Tw.fixed
            , Tw.z_10

            --, Bp.dark
            --    [ Tw.bg_dark
            --    ]
            , Bp.md
                [ Tw.w_64
                , Tw.block
                , if onDocsPage then
                    Tw.sticky

                  else
                    Tw.hidden
                , Tw.flex_shrink_0
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


view : Bool -> Bool -> Maybe String -> TableOfContents Data -> Html msg
view showMobileMenu onDocsPage current toc =
    surround showMobileMenu
        onDocsPage
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
                    , Tw.font_semibold
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
