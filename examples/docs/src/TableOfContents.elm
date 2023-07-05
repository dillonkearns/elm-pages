module TableOfContents exposing (..)

import BackendTask exposing (BackendTask)
import BackendTask.File
import Css
import FatalError exposing (FatalError)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import List.Extra
import Markdown.Block as Block exposing (Block, Inline)
import Markdown.Parser
import NextPrevious
import Svg.Styled as Svg
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Breakpoints as Bp
import Tailwind.Theme as Theme
import Tailwind.Utilities as Tw


backendTask :
    BackendTask FatalError (List { file | filePath : String, slug : String })
    -> BackendTask FatalError (TableOfContents Data)
backendTask docFiles =
    docFiles
        |> BackendTask.map
            (\sections ->
                sections
                    |> List.map
                        (\section ->
                            BackendTask.File.bodyWithoutFrontmatter
                                section.filePath
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen (headingsDecoder section.slug)
                        )
            )
        |> BackendTask.resolve


headingsDecoder : String -> String -> BackendTask FatalError (Entry Data)
headingsDecoder slug rawBody =
    rawBody
        |> Markdown.Parser.parse
        |> Result.mapError (\_ -> FatalError.fromString "Markdown parsing error")
        |> Result.map gatherHeadings
        |> Result.andThen (nameAndTopLevel slug >> Result.mapError FatalError.fromString)
        |> BackendTask.fromResult


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
            Err ("Missing H1 heading for " ++ slug)


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
            , Tw.bg_color Theme.white
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
                [ Tw.border_color Theme.gray_200
                , Tw.w_full
                , Tw.p_4
                , Tw.pb_40
                , Tw.h_full
                , Tw.overflow_y_auto
                , Bp.md
                    [ Tw.pb_16
                    ]
                ]
            ]
            children
        ]


onThisPage : Bool -> Bool -> Maybe String -> TableOfContents Data -> Html msg
onThisPage showMobileMenu onDocsPage current toc =
    let
        currentAnchorId : String
        currentAnchorId =
            Maybe.withDefault "what-is-elm-pages" current

        subHeadings : List (Entry Data)
        subHeadings =
            toc
                |> List.filterMap
                    (\(Entry data children) ->
                        if data.anchorId == currentAnchorId then
                            Just children

                        else
                            Nothing
                    )
                |> List.head
                |> Maybe.withDefault []
    in
    div []
        [ div
            [ css
                [ Tw.hidden
                , Bp.lg
                    [ Tw.sticky
                    , Tw.top_28
                    , Tw.order_1
                    , Tw.mt_10
                    , Tw.block
                    , Tw.w_56
                    , Tw.flex_shrink_0
                    , Tw.self_start
                    , Tw.overflow_auto
                    ]
                ]
            ]
            [ nav
                [ css
                    [ Tw.mb_2
                    , Tw.text_sm
                    , Tw.font_bold
                    ]
                ]
                [ text "On this page" ]
            , ul []
                (subHeadings
                    |> List.map onThisPageItem
                )
            ]
        ]


onThisPageDetails : Bool -> Bool -> Maybe String -> TableOfContents Data -> Html msg
onThisPageDetails showMobileMenu onDocsPage current toc =
    let
        currentAnchorId : String
        currentAnchorId =
            Maybe.withDefault "what-is-elm-pages" current

        subHeadings : List (Entry Data)
        subHeadings =
            toc
                |> List.filterMap
                    (\(Entry data children) ->
                        if data.anchorId == currentAnchorId then
                            Just children

                        else
                            Nothing
                    )
                |> List.head
                |> Maybe.withDefault []
    in
    div
        [ css
            [ --Tw.sticky,
              Tw.top_28
            , Tw.order_1
            , Tw.mt_10
            , Tw.block
            , Tw.w_full

            --, Tw.flex_shrink_0
            , Tw.self_start
            , Tw.overflow_auto
            , Bp.lg
                [ Tw.hidden
                ]
            ]
        ]
        [ details
            [ css
                [ Tw.flex
                , Tw.h_full
                , Tw.flex_col
                , Bp.lg
                    [ Tw.ml_80
                    , Tw.mt_4
                    , Tw.hidden
                    ]
                ]
            ]
            [ summary
                [ css
                    [ Css.listStyle Css.none
                    , Tw.flex
                    , Tw.cursor_pointer
                    , Tw.select_none
                    , Tw.items_center
                    , Tw.gap_2
                    , Tw.border_b
                    , Tw.px_2
                    , Tw.py_3
                    , Tw.text_sm
                    , Tw.font_medium
                    , Css.active
                        [--Tw.bg_gray_100
                        ]
                    , Css.hover
                        [--Tw.text_color
                        ]
                    ]
                ]
                [ div
                    [ css
                        [ Tw.flex
                        , Tw.items_center
                        , Tw.gap_2
                        ]
                    ]
                    [ Svg.svg
                        [ Attr.attribute "aria-hidden" "true"
                        , SvgAttr.class "summary-closed"
                        , SvgAttr.css
                            [ Tw.h_5
                            , Tw.w_5
                            ]
                        ]
                        [ NextPrevious.rightArrow
                        ]
                    , Svg.svg
                        [ Attr.attribute "aria-hidden" "true"
                        , SvgAttr.class "summary-open"
                        , SvgAttr.css
                            [ Tw.hidden
                            , Tw.h_5
                            , Tw.w_5
                            ]
                        ]
                        [ NextPrevious.downArrow
                        ]
                    ]
                , div
                    [ css
                        [ Tw.whitespace_nowrap
                        ]
                    ]
                    [ text "On this page" ]
                ]
            , ul
                [ css
                    [ Tw.pl_9
                    ]
                ]
                (subHeadings
                    |> List.map onThisPageItem
                )
            ]
        ]


onThisPageItem : Entry Data -> Html msg
onThisPageItem (Entry subHeading _) =
    li []
        [ a
            [ Attr.href ("#" ++ subHeading.anchorId)
            , css
                [ Tw.block
                , Tw.py_1
                , Tw.text_sm
                , Tw.text_color Theme.gray_500
                , Css.active
                    [ Tw.bg_color Theme.gray_200
                    , Tw.font_semibold
                    ]
                , Css.hover
                    [ Tw.text_color Theme.black
                    , Tw.bg_color Theme.gray_100
                    ]
                ]
            ]
            [ text subHeading.name ]
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
            , Tw.text_color Theme.gray_900
            , Tw.rounded_lg
            ]
        ]
        [ item isCurrent ("/docs/" ++ data.anchorId) data.name
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
                    [ Tw.bg_color Theme.gray_200
                    , Tw.font_semibold
                    ]

              else
                Css.batch
                    [ Css.hover
                        [ Tw.text_color Theme.black
                        , Tw.bg_color Theme.gray_100
                        ]
                    , Tw.text_color Theme.gray_500
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
