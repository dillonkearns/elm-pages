module TableOfContents exposing (..)

import BackendTask exposing (BackendTask)
import BackendTask.File
import FatalError exposing (FatalError)
import Html exposing (..)
import Html.Attributes as Attr
import List.Extra
import Markdown.Block as Block exposing (Block, Inline)
import Markdown.Parser


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
    inlines
        |> Block.extractInlineText


surround : Bool -> Bool -> List (Html msg) -> Html msg
surround showMobileMenu onDocsPage children =
    aside
        [ Attr.class
            (String.join " "
                [ "h-screen bg-white shrink-0 top-0 pt-16 w-full z-10"
                , "fixed"
                , "md:w-64 md:shrink-0"
                , if showMobileMenu then
                    "block"

                  else
                    "hidden"
                , "md:block"
                , if onDocsPage then
                    "md:!sticky"

                  else
                    "md:hidden"
                ]
            )
        ]
        [ div
            [ Attr.class "border-gray-200 w-full p-4 pb-40 h-full overflow-y-auto md:pb-16"
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
        [ Attr.class "space-y-3 text-gray-900 rounded-lg"
        ]
        [ item isCurrent ("/docs/" ++ data.anchorId) data.name
        , ul
            [ Attr.class "space-y-3"
            ]
            (children
                |> List.map (level2Entry data.anchorId)
            )
        ]


item : Bool -> String -> String -> Html msg
item isCurrent href body =
    a
        [ Attr.href href
        , Attr.class
            ("block w-full text-left text-base no-underline mt-1 p-2 rounded select-none outline-none "
                ++ (if isCurrent then
                        "bg-gray-200 font-semibold"

                    else
                        "hover:text-black hover:bg-gray-100 text-gray-500"
                   )
            )
        ]
        [ text body ]


level2Entry : String -> Entry Data -> Html msg
level2Entry parentPath (Entry data children) =
    li
        [ Attr.class "ml-4"
        ]
        [ item False ("/docs/" ++ parentPath ++ "#" ++ data.anchorId) data.name
        ]
