module Markdown.Parser exposing (..)

import Markdown.CodeBlock
import Markdown.Inlines as Inlines exposing (StyledString)
import Markdown.List
import Parser
import Parser.Advanced as Advanced exposing ((|.), (|=), Nestable(..), Step(..), andThen, chompUntil, chompWhile, getChompedString, inContext, int, lazy, loop, map, multiComment, oneOf, problem, succeed, symbol, token)
import XmlParser exposing (Node(..))


type Decoder a
    = Decoder (String -> List Attribute -> List Block -> Result String a)


htmlSucceed : view -> Decoder view
htmlSucceed value =
    Decoder (\_ _ _ -> Ok value)


htmlOneOf : List (Decoder view) -> Decoder view
htmlOneOf decoders =
    List.foldl
        (\(Decoder decoder) (Decoder soFar) ->
            Decoder
                (\tag attributes children ->
                    resultOr (decoder tag attributes children) (soFar tag attributes children)
                )
        )
        (Decoder (\tag attributes children -> Err "No Html Decoders succeeded in oneOf."))
        decoders



-- (\decoder soFar -> soFar)
-- (\_ _ -> Debug.todo "")
-- (\node -> Err "No decoders")
-- decoders


resultOr : Result e a -> Result e a -> Result e a
resultOr ra rb =
    case ra of
        Err _ ->
            rb

        Ok _ ->
            ra


htmlTag : String -> view -> Decoder view
htmlTag expectedTag a =
    Decoder
        (\tag attributes children ->
            if tag == expectedTag then
                Ok a

            else
                Err ("Expected " ++ expectedTag ++ " but was " ++ tag)
        )


type alias Renderer view =
    { heading : Int -> List view -> view
    , raw : List view -> view
    , todo : view
    , htmlDecoder : Decoder (List view -> view)
    , plain : String -> view
    , code : String -> view
    , bold : String -> view
    , italic : String -> view

    -- TODO make this a `Result` so users can validate links
    , link : { title : Maybe String, destination : String } -> String -> view
    , list : List view -> view
    , codeBlock : { body : String, language : Maybe String } -> view
    }


renderStyled : Renderer view -> List StyledString -> List view
renderStyled renderer styledStrings =
    styledStrings
        |> List.foldr (foldThing renderer) []


foldThing : Renderer view -> StyledString -> List view -> List view
foldThing renderer { style, string } soFar =
    case style.link of
        Just link ->
            renderer.link link string
                :: soFar

        Nothing ->
            if style.isBold then
                renderer.bold string
                    :: soFar

            else if style.isItalic then
                renderer.italic string
                    :: soFar

            else if style.isCode then
                renderer.code string
                    :: soFar

            else
                renderer.plain string
                    :: soFar


renderHelper :
    Renderer view
    -> List Block
    -> List (Result String view)
renderHelper renderer blocks =
    List.map
        (\block ->
            case block of
                Heading level content ->
                    renderer.heading level (renderStyled renderer content)
                        |> Ok

                Body content ->
                    renderStyled renderer content
                        |> renderer.raw
                        |> Ok

                Html tag attributes children ->
                    renderHtmlNode renderer tag attributes (children |> List.reverse)

                ListBlock items ->
                    items
                        |> List.map (renderStyled renderer)
                        |> List.map renderer.raw
                        |> renderer.list
                        |> Ok

                CodeBlock codeBlock ->
                    codeBlock
                        |> renderer.codeBlock
                        |> Ok
        )
        blocks


render :
    Renderer view
    -> String
    -> Result String (List view)
render renderer markdownText =
    markdownText
        |> parse
        |> Result.mapError deadEndsToString
        |> Result.andThen
            (\markdownAst ->
                markdownAst
                    |> renderHelper renderer
                    |> combineResults
            )


combineResults : List (Result x a) -> Result x (List a)
combineResults =
    List.foldr (Result.map2 (::)) (Ok [])


deadEndsToString : List (Advanced.DeadEnd String Parser.Problem) -> String
deadEndsToString deadEnds =
    deadEnds
        |> List.map deadEndToString
        |> String.join "\n"


deadEndToString : Advanced.DeadEnd String Parser.Problem -> String
deadEndToString deadEnd =
    "Problem at row " ++ String.fromInt deadEnd.row ++ "\n" ++ problemToString deadEnd.problem


problemToString : Parser.Problem -> String
problemToString problem =
    case problem of
        Parser.Expecting string ->
            "Expecting " ++ string

        Parser.ExpectingInt ->
            "Expecting int"

        Parser.ExpectingHex ->
            "Expecting hex"

        Parser.ExpectingOctal ->
            "Expecting octal"

        Parser.ExpectingBinary ->
            "Expecting binary"

        Parser.ExpectingFloat ->
            "Expecting float"

        Parser.ExpectingNumber ->
            "Expecting number"

        Parser.ExpectingVariable ->
            "Expecting variable"

        Parser.ExpectingSymbol string ->
            "Expecting symbol " ++ string

        Parser.ExpectingKeyword string ->
            "Expecting keyword " ++ string

        Parser.ExpectingEnd ->
            "Expecting keyword end"

        Parser.UnexpectedChar ->
            "Unexpected char"

        Parser.Problem problemDescription ->
            problemDescription

        Parser.BadRepeat ->
            "Bad repeat"


renderHtmlNode : Renderer view -> String -> List Attribute -> List Block -> Result String view
renderHtmlNode renderer tag attributes children =
    useRed tag
        attributes
        children
        renderer.htmlDecoder
        (renderHelper renderer children)


useRed : String -> List Attribute -> List Block -> Decoder (List view -> view) -> List (Result String view) -> Result String view
useRed tag attributes children (Decoder redRenderer) renderedChildren =
    renderedChildren
        |> combineResults
        |> Result.andThen
            (\okChildren ->
                redRenderer tag attributes children
                    |> Result.map
                        (\myRenderer -> myRenderer okChildren)
            )


type alias Parser a =
    Advanced.Parser String Parser.Problem a


type Block
    = Heading Int (List StyledString)
    | Body (List StyledString)
    | Html String (List Attribute) (List Block)
    | ListBlock (List (List Inlines.StyledString))
    | CodeBlock Markdown.CodeBlock.CodeBlock


type alias Attribute =
    { name : String, value : String }


plainLine : Parser (List Block)
plainLine =
    succeed identity
        |= Advanced.getChompedString (Advanced.chompUntilEndOr "\n")
        |> Advanced.andThen
            (\line ->
                case Advanced.run Inlines.parse line of
                    Ok styledLine ->
                        succeed styledLine

                    Err error ->
                        problem (Parser.Expecting "....??? TODO")
            )
        |> Advanced.map Body
        |> Advanced.map List.singleton


listBlock : Parser Block
listBlock =
    Markdown.List.parser
        |> map ListBlock


blankLine : Parser Block
blankLine =
    succeed (Body [])
        |. symbol (Advanced.Token "\n" (Parser.Expecting "\n"))


htmlParser : Parser Block
htmlParser =
    XmlParser.element
        |> xmlNodeToHtmlNode


toTopLevelHtml : String -> List Attribute -> List Block -> Block
toTopLevelHtml tag attributes children =
    Html tag attributes children


xmlNodeToHtmlNode : Parser Node -> Parser Block
xmlNodeToHtmlNode parser =
    Advanced.andThen
        (\xmlNode ->
            case xmlNode of
                XmlParser.Text innerText ->
                    -- TODO is this right?
                    Body
                        -- TODO remove hardcoding
                        [ { string = innerText
                          , style =
                                { isCode = False
                                , isBold = False
                                , isItalic = False
                                , link = Nothing
                                }
                          }
                        ]
                        |> Advanced.succeed

                XmlParser.Element tag attributes children ->
                    Advanced.andThen
                        (\parsedChildren ->
                            Advanced.succeed
                                (Html tag
                                    attributes
                                    parsedChildren
                                )
                        )
                        (nodesToBlocksParser children)
        )
        parser


nodesToBlocksParser : List Node -> Parser (List Block)
nodesToBlocksParser children =
    children
        |> List.map childToParser
        |> combine
        |> Advanced.map List.concat


combine : List (Parser a) -> Parser (List a)
combine list =
    list
        |> List.foldl
            (\parser listParser ->
                listParser
                    |> Advanced.andThen
                        (\soFar ->
                            parser
                                |> Advanced.map (\a -> a :: soFar)
                        )
            )
            (Advanced.succeed [])


childToParser : Node -> Parser (List Block)
childToParser node =
    case node of
        Element tag attributes children ->
            nodesToBlocksParser children
                |> Advanced.andThen
                    (\childrenAsBlocks ->
                        Advanced.succeed [ Html tag attributes childrenAsBlocks ]
                    )

        Text innerText ->
            case Advanced.run multiParser innerText of
                Ok value ->
                    succeed value

                Err error ->
                    Advanced.problem (Parser.Expecting (error |> Debug.toString))


multiParser : Parser (List Block)
multiParser =
    loop [ [] ] statementsHelp
        |. succeed Advanced.end
        -- TODO find a more elegant way to exclude empty blocks for each blank lines
        |> map (List.filter (\item -> item /= Body []))


statementsHelp : List (List Block) -> Parser (Step (List (List Block)) (List Block))
statementsHelp revStmts =
    oneOf
        [ succeed
            (\offsetBefore stmts offsetAfter ->
                let
                    madeProgress =
                        offsetAfter > offsetBefore
                in
                if madeProgress then
                    Loop (stmts :: revStmts)

                else
                    Done
                        (List.reverse (stmts :: revStmts)
                            |> List.concat
                        )
            )
            |= Advanced.getOffset
            |= oneOf
                [ listBlock |> map List.singleton
                , blankLine |> map List.singleton
                , heading |> map List.singleton
                , Markdown.CodeBlock.parser |> map CodeBlock |> map List.singleton
                , htmlParser |> map List.singleton
                , htmlParser |> map List.singleton
                , plainLine
                ]
            |= Advanced.getOffset

        -- TODO this is causing files to require newlines
        -- at the end... how do I avoid this?
        -- |. symbol (Advanced.Token "\n" (Parser.Expecting "newline"))
        , succeed ()
            |> map
                (\_ ->
                    Done
                        (List.reverse revStmts
                            |> List.concat
                        )
                )
        ]


heading : Parser Block
heading =
    succeed Heading
        |. symbol (Advanced.Token "#" (Parser.Expecting "#"))
        |= (getChompedString
                (succeed ()
                    |. chompWhile (\c -> c == '#')
                )
                |> andThen
                    (\additionalHashes ->
                        let
                            level =
                                String.length additionalHashes + 1
                        in
                        if level >= 7 then
                            Advanced.problem (Parser.Expecting "heading with < 7 #'s")

                        else
                            succeed level
                    )
           )
        |. chompWhile (\c -> c == ' ')
        |= (getChompedString
                (succeed ()
                    -- |. chompWhile (\c -> c /= '\n')
                    |. Advanced.chompUntilEndOr "\n"
                )
                |> Advanced.andThen
                    (\headingText ->
                        let
                            result =
                                headingText
                                    |> Advanced.run Inlines.parse
                        in
                        case result of
                            Ok styled ->
                                succeed styled

                            Err error ->
                                problem (Parser.Expecting "TODO")
                    )
           )


parse : String -> Result (List (Advanced.DeadEnd String Parser.Problem)) (List Block)
parse input =
    Advanced.run multiParser input
