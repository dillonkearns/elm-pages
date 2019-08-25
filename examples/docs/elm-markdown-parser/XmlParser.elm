module XmlParser exposing
    ( Xml, ProcessingInstruction, DocType, DocTypeDefinition(..), Node(..), Attribute
    , parse
    , format
    , element
    )

{-| The XML Parser.


# Types

@docs Xml, ProcessingInstruction, DocType, DocTypeDefinition, Node, Attribute


# Parse

@docs parse


# Format

@docs format

-}

import Char
import Dict exposing (Dict)
import Hex
import Parser as Parser
import Parser.Advanced as Advanced exposing ((|.), (|=), Nestable(..), Step(..), andThen, chompUntil, chompWhile, getChompedString, inContext, int, lazy, loop, map, multiComment, oneOf, problem, succeed, token)
import Set exposing (Set)


{-| This represents the entire XML structure.

  - processingInstructions: `<?xml-stylesheet type="text/xsl" href="style.xsl"?>`
  - docType: `<!DOCTYPE root SYSTEM "foo.xml">`
  - root: `<root><foo/></root>`

-}
type alias Xml =
    { processingInstructions : List ProcessingInstruction
    , docType : Maybe DocType
    , root : Node
    }


{-| Processing Instruction such as `<?xml-stylesheet type="text/xsl" href="style.xsl"?>`.

The example above is parsed as `{ name = "xml-stylesheet", value = "type=\"text/xsl\" href=\"style.xsl\"" }`.
The value (presudo attributes) should be parsed by application.

-}
type alias ProcessingInstruction =
    { name : String
    , value : String
    }


{-| Doc Type Decralation starting with "<!DOCTYPE".

This contains root element name and rest of details as `DocTypeDefinition`.

-}
type alias DocType =
    { rootElementName : String
    , definition : DocTypeDefinition
    }


{-| DTD (Doc Type Definition)

  - Public: `<!DOCTYPE root PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">`
  - System: `<!DOCTYPE root SYSTEM "foo.xml">`
  - Custom: `<!DOCTYPE root [ <!ELEMENT ...> ]>`

-}
type DocTypeDefinition
    = Public String String (Maybe String)
    | System String (Maybe String)
    | Custom String


{-| Node is either a element such as `<a name="value">foo</a>` or text such as `foo`.
-}
type Node
    = Element String (List Attribute) (List Node)
    | Text String


{-| Attribute such as `name="value"`
-}
type alias Attribute =
    { name : String, value : String }


type alias Parser a =
    Advanced.Parser String Parser.Problem a


type alias DeadEnd =
    Advanced.DeadEnd String Parser.Problem


type Count
    = AtLeast Int


{-| Parse XML string.

`<?xml ... ?>` and `<!DOCTYPE ... >` is optional so you don't need to ensure them.

    > import XmlParser
    > XmlParser.parse """<a name="value">foo</a>"""
    Ok { processingInstructions = [], docType = Nothing, root = Element "a" ([{ name = "name", value = "value" }]) ([Text "foo"]) }

-}
parse : String -> Result (List DeadEnd) Xml
parse source =
    Advanced.run xml source


xml : Parser Xml
xml =
    inContext "xml" <|
        succeed Xml
            |. whiteSpace
            |= repeat zeroOrMore
                (succeed identity
                    |= processingInstruction
                    |. whiteSpace
                )
            |. repeat zeroOrMore (oneOf [ whiteSpace1, comment ])
            |= maybe docType
            |. repeat zeroOrMore (oneOf [ whiteSpace1, comment ])
            |= element
            |. repeat zeroOrMore (oneOf [ whiteSpace1, comment ])
            |. end


processingInstruction : Parser ProcessingInstruction
processingInstruction =
    inContext "processingInstruction" <|
        succeed ProcessingInstruction
            |. symbol "<?"
            |= processingInstructionName
            |. symbol " "
            |= processingInstructionValue


processingInstructionName : Parser String
processingInstructionName =
    inContext "processingInstructionName" <|
        keep oneOrMore (\c -> c /= ' ')


processingInstructionValue : Parser String
processingInstructionValue =
    inContext "processingInstructionValue" <|
        oneOf
            [ succeed ""
                |. symbol "?>"
            , symbol "?"
                |> andThen
                    (\_ ->
                        processingInstructionValue
                            |> map (\tail -> "?" ++ tail)
                    )
            , succeed (++)
                |= keep zeroOrMore (\c -> c /= '?')
                |= lazy (\_ -> processingInstructionValue)
            ]


docType : Parser DocType
docType =
    inContext "docType" <|
        succeed DocType
            |. symbol "<!DOCTYPE"
            |. whiteSpace
            |= tagName
            |. whiteSpace
            |= docTypeDefinition
            |. whiteSpace
            |. symbol ">"


docTypeDefinition : Parser DocTypeDefinition
docTypeDefinition =
    inContext "docTypeDefinition" <|
        oneOf
            [ succeed Public
                |. keyword "PUBLIC"
                |. whiteSpace
                |= publicIdentifier
                |. whiteSpace
                |= docTypeExternalSubset
                |. whiteSpace
                |= maybe docTypeInternalSubset
            , succeed System
                |. keyword "SYSTEM"
                |. whiteSpace
                |= docTypeExternalSubset
                |. whiteSpace
                |= maybe docTypeInternalSubset
            , succeed Custom
                |= docTypeInternalSubset
            ]


publicIdentifier : Parser String
publicIdentifier =
    inContext "publicIdentifier" <|
        succeed identity
            |. symbol "\""
            |= keep zeroOrMore (\c -> c /= '"')
            |. symbol "\""


docTypeExternalSubset : Parser String
docTypeExternalSubset =
    inContext "docTypeExternalSubset" <|
        succeed identity
            |. symbol "\""
            |= keep zeroOrMore (\c -> c /= '"')
            |. symbol "\""


docTypeInternalSubset : Parser String
docTypeInternalSubset =
    inContext "docTypeInternalSubset" <|
        succeed identity
            |. symbol "["
            |= keep zeroOrMore (\c -> c /= ']')
            |. symbol "]"


cdata : Parser String
cdata =
    inContext "cdata" <|
        succeed identity
            |. symbol "<![CDATA["
            |= cdataContent


cdataContent : Parser String
cdataContent =
    inContext "cdataContent" <|
        oneOf
            [ succeed ""
                |. symbol "]]>"
            , symbol "]]"
                |> andThen
                    (\_ ->
                        cdataContent
                            |> map (\tail -> "]]" ++ tail)
                    )
            , symbol "]"
                |> andThen
                    (\_ ->
                        cdataContent
                            |> map (\tail -> "]" ++ tail)
                    )
            , succeed (++)
                |= keep zeroOrMore (\c -> c /= ']')
                |= lazy (\_ -> cdataContent)
            ]


element : Parser Node
element =
    inContext "element" <|
        succeed identity
            |. symbol "<"
            |= (tagName
                    |> andThen
                        (\startTagName ->
                            succeed (Element startTagName)
                                |. whiteSpace
                                |= attributes Set.empty
                                |. whiteSpace
                                |= oneOf
                                    [ succeed []
                                        |. symbol "/>"
                                    , succeed identity
                                        |. symbol ">"
                                        |= lazy (\_ -> children startTagName)
                                    ]
                        )
               )


tagName : Parser String
tagName =
    inContext "tagName" <|
        keep oneOrMore (\c -> not (isWhitespace c) && c /= '/' && c /= '<' && c /= '>' && c /= '"' && c /= '\'' && c /= '=')


children : String -> Parser (List Node)
children startTagName =
    inContext "children" <|
        oneOf
            [ succeed []
                |. closingTag startTagName
            , textNodeString
                |> andThen
                    (\maybeString ->
                        case maybeString of
                            Just s ->
                                succeed (\rest -> Text s :: rest)
                                    |= children startTagName

                            Nothing ->
                                succeed []
                                    |. closingTag startTagName
                    )
            , lazy
                (\_ ->
                    succeed (::)
                        |= element
                        |= children startTagName
                )
            ]


closingTag : String -> Parser ()
closingTag startTagName =
    inContext "closingTag" <|
        succeed ()
            |. symbol "</"
            |. whiteSpace
            |. (tagName
                    |> andThen
                        (\endTagName ->
                            if startTagName == endTagName then
                                succeed ()

                            else
                                fail ("tag name mismatch: " ++ startTagName ++ " and " ++ endTagName)
                        )
               )
            |. whiteSpace
            |. symbol ">"


textString : Char -> Parser String
textString end_ =
    inContext "textString" <|
        (keep zeroOrMore (\c -> c /= end_ && c /= '&')
            |> andThen
                (\s ->
                    oneOf
                        [ succeed String.cons
                            |= escapedChar end_
                            |= lazy (\_ -> textString end_)
                        , succeed s
                        ]
                )
        )


textNodeString : Parser (Maybe String)
textNodeString =
    inContext "textNodeString" <|
        oneOf
            [ succeed
                (\s maybeString ->
                    Just (s ++ (maybeString |> Maybe.withDefault ""))
                )
                |= keep oneOrMore (\c -> c /= '<' && c /= '&')
                |= lazy (\_ -> textNodeString)
            , succeed
                (\c maybeString ->
                    Just (String.cons c (maybeString |> Maybe.withDefault ""))
                )
                |= escapedChar '<'
                |= lazy (\_ -> textNodeString)
            , succeed
                (\s maybeString ->
                    let
                        str =
                            s ++ (maybeString |> Maybe.withDefault "")
                    in
                    if str /= "" then
                        Just str

                    else
                        Nothing
                )
                |= cdata
                |= lazy (\_ -> textNodeString)
            , succeed
                (\maybeString ->
                    let
                        str =
                            maybeString |> Maybe.withDefault ""
                    in
                    if str /= "" then
                        Just str

                    else
                        Nothing
                )
                |. comment
                |= lazy (\_ -> textNodeString)
            , succeed Nothing
            ]


escapedChar : Char -> Parser Char
escapedChar end_ =
    inContext "escapedChar" <|
        (succeed identity
            |. symbol "&"
            |= keep oneOrMore (\c -> c /= end_ && c /= ';')
            |> andThen
                (\s ->
                    oneOf
                        [ symbol ";"
                            |> andThen
                                (\_ ->
                                    case decodeEscape s of
                                        Ok c ->
                                            succeed c

                                        Err e ->
                                            problem e
                                )
                        , fail ("Entities must end_ with \";\": &" ++ s)
                        ]
                )
        )


decodeEscape : String -> Result Parser.Problem Char
decodeEscape s =
    if String.startsWith "#x" s then
        s
            |> String.dropLeft 2
            |> Hex.fromString
            |> Result.map Char.fromCode
            |> Result.mapError Parser.Problem

    else if String.startsWith "#" s then
        s
            |> String.dropLeft 1
            |> String.toInt
            |> Maybe.map Char.fromCode
            |> Result.fromMaybe (Parser.Problem <| "Invalid escaped charactor: " ++ s)

    else
        Dict.get s entities
            |> Result.fromMaybe (Parser.Problem <| "No entity named \"&" ++ s ++ ";\" found.")


entities : Dict String Char
entities =
    Dict.fromList
        [ ( "amp", '&' )
        , ( "lt", '<' )
        , ( "gt", '>' )
        , ( "apos", '\'' )
        , ( "quot", '"' )
        ]


attributes : Set String -> Parser (List Attribute)
attributes keys =
    inContext "attributes" <|
        oneOf
            [ attribute
                |> andThen
                    (\attr ->
                        if Set.member attr.name keys then
                            fail ("attribute " ++ attr.name ++ " is duplicated")

                        else
                            succeed ((::) attr)
                                |. whiteSpace
                                |= attributes (Set.insert attr.name keys)
                    )
            , succeed []
            ]


validateAttributes : Set String -> List Attribute -> Maybe String
validateAttributes keys attrs =
    case attrs of
        [] ->
            Nothing

        x :: xs ->
            if Set.member x.name keys then
                Just x.name

            else
                validateAttributes (Set.insert x.name keys) xs


attribute : Parser Attribute
attribute =
    inContext "attribute" <|
        succeed Attribute
            |= attributeName
            |. whiteSpace
            |. symbol "="
            |. whiteSpace
            |= attributeValue


attributeName : Parser String
attributeName =
    inContext "attributeName" <|
        keep oneOrMore (\c -> not (isWhitespace c) && c /= '/' && c /= '<' && c /= '>' && c /= '"' && c /= '\'' && c /= '=')


attributeValue : Parser String
attributeValue =
    inContext "attributeValue" <|
        oneOf
            [ succeed identity
                |. symbol "\""
                |= textString '"'
                |. symbol "\""
            , succeed identity
                |. symbol "'"
                |= textString '\''
                |. symbol "'"
            ]


whiteSpace : Parser ()
whiteSpace =
    ignore zeroOrMore isWhitespace


whiteSpace1 : Parser ()
whiteSpace1 =
    ignore oneOrMore isWhitespace


isWhitespace : Char -> Bool
isWhitespace c =
    c == ' ' || c == '\u{000D}' || c == '\n' || c == '\t'


comment : Parser ()
comment =
    succeed ()
        |. token (toToken "<!--")
        |. chompUntil (toToken "-->")
        |. token (toToken "-->")



-- FORMAT


{-| Convert Xml into String.

This function does NOT insert line breaks or indents for readability.

-}
format : Xml -> String
format doc =
    let
        pi =
            doc.processingInstructions
                |> List.map formatProcessingInstruction
                |> String.join ""

        dt =
            doc.docType
                |> Maybe.map formatDocType
                |> Maybe.withDefault ""

        node =
            formatNode doc.root
    in
    pi ++ dt ++ node


formatProcessingInstruction : ProcessingInstruction -> String
formatProcessingInstruction processingInstruction_ =
    "<?" ++ escape processingInstruction_.name ++ " " ++ escape processingInstruction_.value ++ "?>"


formatDocType : DocType -> String
formatDocType docType_ =
    "<!DOCTYPE " ++ escape docType_.rootElementName ++ " " ++ formatDocTypeDefinition docType_.definition ++ ">"


formatDocTypeDefinition : DocTypeDefinition -> String
formatDocTypeDefinition def =
    case def of
        Public publicIdentifier_ internalSubsetRef maybeInternalSubset ->
            "PUBLIC \""
                ++ escape publicIdentifier_
                ++ "\" \""
                ++ escape internalSubsetRef
                ++ "\""
                ++ (case maybeInternalSubset of
                        Just internalSubset ->
                            " [" ++ escape internalSubset ++ "]"

                        Nothing ->
                            ""
                   )

        System internalSubsetRef maybeInternalSubset ->
            "SYSTEM \""
                ++ escape internalSubsetRef
                ++ "\""
                ++ (case maybeInternalSubset of
                        Just internalSubset ->
                            " [" ++ escape internalSubset ++ "]"

                        Nothing ->
                            ""
                   )

        Custom internalSubset ->
            "[" ++ escape internalSubset ++ "]"


formatNode : Node -> String
formatNode node =
    case node of
        Element tagName_ attributes_ children_ ->
            "<"
                ++ escape tagName_
                ++ " "
                ++ (attributes_ |> List.map formatAttribute |> String.join " ")
                ++ (if children_ == [] then
                        "/>"

                    else
                        ">"
                            ++ (children_ |> List.map formatNode |> String.join "")
                            ++ "</"
                            ++ escape tagName_
                            ++ ">"
                   )

        Text s ->
            escape s


formatAttribute : Attribute -> String
formatAttribute attribute_ =
    escape attribute_.name ++ "=\"" ++ escape attribute_.value ++ "\""


escape : String -> String
escape s =
    s
        |> String.replace "&" "&amp;"
        |> String.replace "<" "&lt;"
        |> String.replace ">" "&gt;"
        |> String.replace "\"" "&quot;"
        |> String.replace "'" "&apos;"



-- UTILITY


maybe : Parser a -> Parser (Maybe a)
maybe parser =
    oneOf
        [ map Just parser
        , succeed Nothing
        ]


zeroOrMore : Count
zeroOrMore =
    AtLeast 0


oneOrMore : Count
oneOrMore =
    AtLeast 1


repeat : Count -> Parser a -> Parser (List a)
repeat count parser =
    case count of
        AtLeast n ->
            loop []
                (\state ->
                    oneOf
                        [ map (\r -> Loop (List.append state [ r ])) parser
                        , map (always (Done state)) (succeed ())
                        ]
                )
                |> andThen
                    (\results ->
                        if n <= List.length results then
                            succeed results

                        else
                            problem Parser.BadRepeat
                    )


keep : Count -> (Char -> Bool) -> Parser String
keep count predicate =
    case count of
        AtLeast n ->
            getChompedString (succeed () |. chompWhile predicate)
                |> andThen
                    (\str ->
                        if n <= String.length str then
                            succeed str

                        else
                            problem Parser.BadRepeat
                    )


ignore : Count -> (Char -> Bool) -> Parser ()
ignore count predicate =
    map (\_ -> ()) (keep count predicate)


fail : String -> Parser a
fail str =
    problem (Parser.Problem str)


symbol : String -> Parser ()
symbol str =
    Advanced.symbol (Advanced.Token str (Parser.ExpectingSymbol str))


keyword : String -> Parser ()
keyword kwd =
    Advanced.keyword (Advanced.Token kwd (Parser.ExpectingKeyword kwd))


end : Parser ()
end =
    Advanced.end Parser.ExpectingEnd


toToken : String -> Advanced.Token Parser.Problem
toToken str =
    Advanced.Token str (Parser.Expecting str)
