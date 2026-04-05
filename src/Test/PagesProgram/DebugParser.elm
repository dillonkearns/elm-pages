module Test.PagesProgram.DebugParser exposing (ElmValue(..), parse, viewValue)

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Parser exposing ((|.), (|=), Parser)
import Set exposing (Set)


type ElmValue
    = ElmString String
    | ElmChar Char
    | ElmInt Int
    | ElmFloat Float
    | ElmBool Bool
    | ElmUnit
    | ElmList (List ElmValue)
    | ElmTuple (List ElmValue)
    | ElmRecord (List ( String, ElmValue ))
    | ElmDict (List ( ElmValue, ElmValue ))
    | ElmSet (List ElmValue)
    | ElmCustom String (List ElmValue)
    | ElmInternals String



-- PARSER


parse : String -> Result String ElmValue
parse input =
    case Parser.run (elmValue |. Parser.end) (String.trim input) of
        Ok value ->
            Ok value

        Err _ ->
            Err input


elmValue : Parser ElmValue
elmValue =
    Parser.oneOf
        [ stringLiteral
        , charLiteral
        , Parser.lazy (\_ -> listLiteral)
        , Parser.lazy (\_ -> recordLiteral)
        , Parser.lazy (\_ -> tupleOrUnit)
        , internals
        , numberLiteral
        , Parser.lazy (\_ -> keywordOrConstructor)
        ]


stringLiteral : Parser ElmValue
stringLiteral =
    Parser.succeed ElmString
        |. Parser.symbol "\""
        |= stringContents
        |. Parser.symbol "\""


stringContents : Parser String
stringContents =
    Parser.loop [] stringHelp
        |> Parser.map (List.reverse >> String.join "")


stringHelp : List String -> Parser (Parser.Step (List String) (List String))
stringHelp revChunks =
    Parser.oneOf
        [ Parser.succeed (\chunk -> Parser.Loop (chunk :: revChunks))
            |. Parser.symbol "\\"
            |= Parser.oneOf
                [ Parser.map (\_ -> "\\") (Parser.symbol "\\")
                , Parser.map (\_ -> "\"") (Parser.symbol "\"")
                , Parser.map (\_ -> "\n") (Parser.symbol "n")
                , Parser.map (\_ -> "\t") (Parser.symbol "t")
                , Parser.map (\_ -> "\u{000D}") (Parser.symbol "r")
                ]
        , Parser.succeed (\chunk -> Parser.Loop (chunk :: revChunks))
            |= (Parser.chompWhile (\c -> c /= '"' && c /= '\\')
                    |> Parser.getChompedString
                    |> Parser.andThen
                        (\s ->
                            if String.isEmpty s then
                                Parser.problem "empty chunk"

                            else
                                Parser.succeed s
                        )
               )
        , Parser.succeed (Parser.Done revChunks)
        ]


charLiteral : Parser ElmValue
charLiteral =
    Parser.succeed ElmChar
        |. Parser.symbol "'"
        |= Parser.oneOf
            [ Parser.succeed '\\'
                |. Parser.symbol "\\\\"
            , Parser.succeed '\''
                |. Parser.symbol "\\'"
            , Parser.succeed '\n'
                |. Parser.symbol "\\n"
            , Parser.succeed '\t'
                |. Parser.symbol "\\t"
            , Parser.succeed '\u{000D}'
                |. Parser.symbol "\\r"
            , Parser.succeed identity
                |= (Parser.chompIf (\c -> c /= '\'')
                        |> Parser.getChompedString
                        |> Parser.andThen
                            (\s ->
                                case String.uncons s of
                                    Just ( c, _ ) ->
                                        Parser.succeed c

                                    Nothing ->
                                        Parser.problem "empty char"
                            )
                   )
            ]
        |. Parser.symbol "'"


listLiteral : Parser ElmValue
listLiteral =
    Parser.succeed ElmList
        |. Parser.symbol "["
        |. spaces
        |= commaSeparated elmValue
        |. spaces
        |. Parser.symbol "]"


recordLiteral : Parser ElmValue
recordLiteral =
    Parser.succeed ElmRecord
        |. Parser.symbol "{"
        |. spaces
        |= commaSeparated recordField
        |. spaces
        |. Parser.symbol "}"


recordField : Parser ( String, ElmValue )
recordField =
    Parser.succeed Tuple.pair
        |= (Parser.variable
                { start = Char.isLower
                , inner = \c -> Char.isAlphaNum c || c == '_'
                , reserved = Set.empty
                }
           )
        |. spaces
        |. Parser.symbol "="
        |. spaces
        |= elmValue


tupleOrUnit : Parser ElmValue
tupleOrUnit =
    Parser.succeed identity
        |. Parser.symbol "("
        |. spaces
        |= Parser.oneOf
            [ Parser.succeed ElmUnit
                |. Parser.symbol ")"
            , Parser.succeed identity
                |= elmValue
                |. spaces
                |> Parser.andThen
                    (\first ->
                        Parser.oneOf
                            [ Parser.succeed (wrapTuple first)
                                |. Parser.symbol ","
                                |. spaces
                                |= commaSeparatedAtLeastOne elmValue
                                |. spaces
                                |. Parser.symbol ")"
                            , Parser.succeed first
                                |. spaces
                                |. Parser.symbol ")"
                            ]
                    )
            ]


wrapTuple : ElmValue -> List ElmValue -> ElmValue
wrapTuple first rest =
    ElmTuple (first :: rest)


internals : Parser ElmValue
internals =
    Parser.succeed ElmInternals
        |. Parser.symbol "<"
        |= (Parser.chompWhile (\c -> c /= '>')
                |> Parser.getChompedString
           )
        |. Parser.symbol ">"


numberLiteral : Parser ElmValue
numberLiteral =
    Parser.oneOf
        [ Parser.succeed (ElmFloat (-1 / 0))
            |. Parser.symbol "-Infinity"
        , Parser.succeed identity
            |. Parser.symbol "-"
            |= Parser.oneOf
                [ Parser.succeed identity
                    |= (Parser.chompWhile (\c -> Char.isDigit c || c == '.')
                            |> Parser.getChompedString
                       )
                    |> Parser.andThen parseNegativeNumber
                ]
        , Parser.succeed (ElmFloat (1 / 0))
            |. Parser.keyword "Infinity"
        , Parser.succeed (ElmFloat (0 / 0))
            |. Parser.keyword "NaN"
        , positiveNumber
        ]


positiveNumber : Parser ElmValue
positiveNumber =
    Parser.succeed identity
        |= (Parser.chompIf Char.isDigit
                |> Parser.getChompedString
                |> Parser.andThen
                    (\firstDigit ->
                        Parser.succeed (\rest -> firstDigit ++ rest)
                            |= (Parser.chompWhile (\c -> Char.isDigit c || c == '.')
                                    |> Parser.getChompedString
                               )
                    )
           )
        |> Parser.andThen parsePositiveNumber


parseNegativeNumber : String -> Parser ElmValue
parseNegativeNumber digits =
    if String.contains "." digits then
        case String.toFloat digits of
            Just f ->
                Parser.succeed (ElmFloat -f)

            Nothing ->
                Parser.problem ("Invalid number: -" ++ digits)

    else
        case String.toInt digits of
            Just i ->
                Parser.succeed (ElmInt -i)

            Nothing ->
                case String.toFloat digits of
                    Just f ->
                        Parser.succeed (ElmFloat -f)

                    Nothing ->
                        Parser.problem ("Invalid number: -" ++ digits)


parsePositiveNumber : String -> Parser ElmValue
parsePositiveNumber digits =
    if String.contains "." digits then
        case String.toFloat digits of
            Just f ->
                Parser.succeed (ElmFloat f)

            Nothing ->
                Parser.problem ("Invalid number: " ++ digits)

    else
        case String.toInt digits of
            Just i ->
                Parser.succeed (ElmInt i)

            Nothing ->
                case String.toFloat digits of
                    Just f ->
                        Parser.succeed (ElmFloat f)

                    Nothing ->
                        Parser.problem ("Invalid number: " ++ digits)


keywordOrConstructor : Parser ElmValue
keywordOrConstructor =
    Parser.succeed identity
        |= constructorName
        |> Parser.andThen
            (\name ->
                case name of
                    "True" ->
                        Parser.succeed (ElmBool True)

                    "False" ->
                        Parser.succeed (ElmBool False)

                    "Dict.fromList" ->
                        Parser.succeed identity
                            |. spaces
                            |= dictList

                    "Set.fromList" ->
                        Parser.succeed identity
                            |. spaces
                            |= setList

                    _ ->
                        Parser.succeed (ElmCustom name)
                            |= constructorArgs
            )


constructorName : Parser String
constructorName =
    Parser.variable
        { start = Char.isUpper
        , inner = \c -> Char.isAlphaNum c || c == '_' || c == '.'
        , reserved = Set.empty
        }


constructorArgs : Parser (List ElmValue)
constructorArgs =
    Parser.loop [] constructorArgsHelp
        |> Parser.map List.reverse


constructorArgsHelp : List ElmValue -> Parser (Parser.Step (List ElmValue) (List ElmValue))
constructorArgsHelp revArgs =
    Parser.oneOf
        [ Parser.succeed (\arg -> Parser.Loop (arg :: revArgs))
            |. Parser.backtrackable (Parser.succeed () |. Parser.symbol " " |. spaces)
            |= atom
        , Parser.succeed (Parser.Done revArgs)
        ]


{-| An atom is a self-delimiting value that can appear as a constructor argument
without parentheses. Bare constructors with no args (like Nothing, True, False)
count, but constructor applications need parens.
-}
atom : Parser ElmValue
atom =
    Parser.oneOf
        [ stringLiteral
        , charLiteral
        , listLiteral
        , recordLiteral
        , tupleOrUnit
        , internals
        , atomNumber
        , atomKeyword
        ]


{-| Numbers as constructor arguments. Negative numbers must be parenthesized
in Debug.toString output when they appear as constructor args.
-}
atomNumber : Parser ElmValue
atomNumber =
    positiveNumber


{-| Keywords/constructors as atoms. Does NOT consume further arguments,
because in atom position `Just Nothing` means Just is the outer constructor
and Nothing is a zero-arg atom argument.
-}
atomKeyword : Parser ElmValue
atomKeyword =
    Parser.succeed identity
        |= constructorName
        |> Parser.andThen
            (\name ->
                case name of
                    "True" ->
                        Parser.succeed (ElmBool True)

                    "False" ->
                        Parser.succeed (ElmBool False)

                    "NaN" ->
                        Parser.succeed (ElmFloat (0 / 0))

                    "Infinity" ->
                        Parser.succeed (ElmFloat (1 / 0))

                    _ ->
                        Parser.succeed (ElmCustom name [])
            )


dictList : Parser ElmValue
dictList =
    Parser.succeed ElmDict
        |. Parser.symbol "["
        |. spaces
        |= commaSeparated dictEntry
        |. spaces
        |. Parser.symbol "]"


dictEntry : Parser ( ElmValue, ElmValue )
dictEntry =
    Parser.succeed Tuple.pair
        |. Parser.symbol "("
        |. spaces
        |= elmValue
        |. spaces
        |. Parser.symbol ","
        |. spaces
        |= elmValue
        |. spaces
        |. Parser.symbol ")"


setList : Parser ElmValue
setList =
    Parser.succeed ElmSet
        |. Parser.symbol "["
        |. spaces
        |= commaSeparated elmValue
        |. spaces
        |. Parser.symbol "]"


commaSeparated : Parser a -> Parser (List a)
commaSeparated itemParser =
    Parser.oneOf
        [ commaSeparatedAtLeastOne itemParser
        , Parser.succeed []
        ]


commaSeparatedAtLeastOne : Parser a -> Parser (List a)
commaSeparatedAtLeastOne itemParser =
    Parser.succeed (::)
        |= itemParser
        |= Parser.loop []
            (\revItems ->
                Parser.oneOf
                    [ Parser.succeed (\item -> Parser.Loop (item :: revItems))
                        |. Parser.backtrackable (Parser.succeed () |. spaces |. Parser.symbol ",")
                        |. spaces
                        |= itemParser
                    , Parser.succeed (Parser.Done (List.reverse revItems))
                    ]
            )


spaces : Parser ()
spaces =
    Parser.chompWhile (\c -> c == ' ' || c == '\n' || c == '\u{000D}' || c == '\t')



-- VIEW


type alias ViewConfig msg =
    { expanded : Set String
    , onToggle : String -> msg
    }


viewValue : ViewConfig msg -> String -> ElmValue -> Html msg
viewValue config path value =
    case value of
        ElmString s ->
            viewString s

        ElmChar c ->
            viewChar c

        ElmInt n ->
            viewNumber (String.fromInt n)

        ElmFloat f ->
            viewNumber (String.fromFloat f)

        ElmBool b ->
            viewKeyword
                (if b then
                    "True"

                 else
                    "False"
                )

        ElmUnit ->
            viewPunctuation "()"

        ElmInternals s ->
            viewInternals s

        ElmList items ->
            viewCollection config path "List" "[" "]" items viewListItem

        ElmTuple items ->
            viewTuple config path items

        ElmRecord fields ->
            viewRecord config path fields

        ElmDict entries ->
            viewDictCollection config path entries

        ElmSet items ->
            viewCollection config path "Set" "[" "]" items viewListItem

        ElmCustom name args ->
            viewCustomType config path name args


viewString : String -> Html msg
viewString s =
    Html.span [ Attr.class "dv-string" ]
        [ Html.text ("\"" ++ s ++ "\"") ]


viewChar : Char -> Html msg
viewChar c =
    Html.span [ Attr.class "dv-string" ]
        [ Html.text ("'" ++ String.fromChar c ++ "'") ]


viewNumber : String -> Html msg
viewNumber n =
    Html.span [ Attr.class "dv-number" ] [ Html.text n ]


viewKeyword : String -> Html msg
viewKeyword k =
    Html.span [ Attr.class "dv-keyword" ] [ Html.text k ]


viewPunctuation : String -> Html msg
viewPunctuation p =
    Html.span [ Attr.class "dv-punct" ] [ Html.text p ]


viewInternals : String -> Html msg
viewInternals s =
    Html.span [ Attr.class "dv-internals" ]
        [ Html.text ("<" ++ s ++ ">") ]


isExpandable : ElmValue -> Bool
isExpandable value =
    case value of
        ElmList items ->
            not (List.isEmpty items)

        ElmRecord fields ->
            not (List.isEmpty fields)

        ElmDict entries ->
            not (List.isEmpty entries)

        ElmSet items ->
            not (List.isEmpty items)

        ElmCustom _ args ->
            not (List.isEmpty args)

        _ ->
            False


viewToggle : ViewConfig msg -> String -> Bool -> Html msg
viewToggle config path isExpanded =
    Html.span
        [ Attr.class "dv-toggle"
        , Html.Events.onClick (config.onToggle path)
        ]
        [ Html.text
            (if isExpanded then
                "\u{25BE} "

             else
                "\u{25B8} "
            )
        ]


viewListItem : ViewConfig msg -> String -> Int -> ElmValue -> Html msg
viewListItem config parentPath index item =
    let
        itemPath =
            parentPath ++ "." ++ String.fromInt index
    in
    viewValue config itemPath item


viewCollection :
    ViewConfig msg
    -> String
    -> String
    -> String
    -> String
    -> List item
    -> (ViewConfig msg -> String -> Int -> item -> Html msg)
    -> Html msg
viewCollection config path typeName open close items viewItem =
    if List.isEmpty items then
        viewPunctuation (open ++ close)

    else
        let
            isExpanded =
                Set.member path config.expanded
        in
        Html.span [ Attr.class "dv-collection" ]
            [ viewToggle config path isExpanded
            , if isExpanded then
                Html.span []
                    [ viewPunctuation open
                    , Html.div [ Attr.class "dv-indent" ]
                        (items
                            |> List.indexedMap
                                (\i item ->
                                    Html.div [ Attr.class "dv-row" ]
                                        [ viewItem config path i item
                                        , if i < List.length items - 1 then
                                            viewPunctuation ","

                                          else
                                            Html.text ""
                                        ]
                                )
                        )
                    , viewPunctuation close
                    ]

              else
                Html.span
                    [ Attr.class "dv-collapsed"
                    , Html.Events.onClick (config.onToggle path)
                    ]
                    [ viewPunctuation (typeName ++ " (" ++ String.fromInt (List.length items) ++ ")") ]
            ]


viewTuple : ViewConfig msg -> String -> List ElmValue -> Html msg
viewTuple config path items =
    Html.span [ Attr.class "dv-inline" ]
        (viewPunctuation "("
            :: (items
                    |> List.indexedMap
                        (\i item ->
                            let
                                itemPath =
                                    path ++ "." ++ String.fromInt i
                            in
                            if i > 0 then
                                Html.span []
                                    [ viewPunctuation ", "
                                    , viewValue config itemPath item
                                    ]

                            else
                                viewValue config itemPath item
                        )
               )
            ++ [ viewPunctuation ")" ]
        )


viewRecord : ViewConfig msg -> String -> List ( String, ElmValue ) -> Html msg
viewRecord config path fields =
    if List.isEmpty fields then
        viewPunctuation "{}"

    else
        let
            isExpanded =
                Set.member path config.expanded
        in
        Html.span [ Attr.class "dv-record" ]
            [ viewToggle config path isExpanded
            , if isExpanded then
                Html.span []
                    [ viewPunctuation "{"
                    , Html.div [ Attr.class "dv-indent" ]
                        (fields
                            |> List.indexedMap
                                (\i ( fieldName, fieldValue ) ->
                                    let
                                        fieldPath =
                                            path ++ "." ++ fieldName
                                    in
                                    Html.div [ Attr.class "dv-row" ]
                                        [ Html.span [ Attr.class "dv-field-name" ]
                                            [ Html.text fieldName ]
                                        , viewPunctuation " = "
                                        , viewValue config fieldPath fieldValue
                                        , if i < List.length fields - 1 then
                                            viewPunctuation ","

                                          else
                                            Html.text ""
                                        ]
                                )
                        )
                    , viewPunctuation "}"
                    ]

              else
                Html.span
                    [ Attr.class "dv-collapsed"
                    , Html.Events.onClick (config.onToggle path)
                    ]
                    [ viewPunctuation "{ "
                    , fields
                        |> List.map
                            (\( fieldName, _ ) ->
                                Html.span [ Attr.class "dv-field-name" ]
                                    [ Html.text fieldName ]
                            )
                        |> List.intersperse (viewPunctuation ", ")
                        |> Html.span []
                    , viewPunctuation " }"
                    ]
            ]


viewDictCollection : ViewConfig msg -> String -> List ( ElmValue, ElmValue ) -> Html msg
viewDictCollection config path entries =
    if List.isEmpty entries then
        viewPunctuation "Dict.fromList []"

    else
        let
            isExpanded =
                Set.member path config.expanded
        in
        Html.span [ Attr.class "dv-collection" ]
            [ viewToggle config path isExpanded
            , if isExpanded then
                Html.span []
                    [ viewPunctuation "Dict"
                    , Html.div [ Attr.class "dv-indent" ]
                        (entries
                            |> List.indexedMap
                                (\i ( key, val ) ->
                                    let
                                        entryPath =
                                            path ++ "." ++ String.fromInt i
                                    in
                                    Html.div [ Attr.class "dv-row" ]
                                        [ viewValue config (entryPath ++ ".k") key
                                        , viewPunctuation " => "
                                        , viewValue config (entryPath ++ ".v") val
                                        , if i < List.length entries - 1 then
                                            viewPunctuation ","

                                          else
                                            Html.text ""
                                        ]
                                )
                        )
                    ]

              else
                Html.span
                    [ Attr.class "dv-collapsed"
                    , Html.Events.onClick (config.onToggle path)
                    ]
                    [ viewPunctuation ("Dict (" ++ String.fromInt (List.length entries) ++ ")") ]
            ]


viewCustomType : ViewConfig msg -> String -> String -> List ElmValue -> Html msg
viewCustomType config path name args =
    if List.isEmpty args then
        Html.span [ Attr.class "dv-constructor" ] [ Html.text name ]

    else
        let
            isExpanded =
                Set.member path config.expanded
        in
        Html.span [ Attr.class "dv-custom" ]
            [ viewToggle config path isExpanded
            , Html.span [ Attr.class "dv-constructor" ] [ Html.text name ]
            , Html.text " "
            , if isExpanded then
                Html.div [ Attr.class "dv-indent" ]
                    (args
                        |> List.indexedMap
                            (\i arg ->
                                let
                                    argPath =
                                        path ++ "." ++ String.fromInt i
                                in
                                Html.div [ Attr.class "dv-row" ]
                                    [ viewValue config argPath arg ]
                            )
                    )

              else
                Html.span
                    [ Attr.class "dv-collapsed"
                    , Html.Events.onClick (config.onToggle path)
                    ]
                    (args
                        |> List.indexedMap
                            (\i arg ->
                                let
                                    argPath =
                                        path ++ "." ++ String.fromInt i
                                in
                                if isExpandable arg then
                                    viewCollapsedPreview arg

                                else
                                    viewValue config argPath arg
                            )
                        |> List.intersperse (Html.text " ")
                    )
            ]


viewCollapsedPreview : ElmValue -> Html msg
viewCollapsedPreview value =
    case value of
        ElmList items ->
            viewPunctuation ("List (" ++ String.fromInt (List.length items) ++ ")")

        ElmRecord fields ->
            Html.span []
                [ viewPunctuation "{ "
                , fields
                    |> List.map
                        (\( fieldName, _ ) ->
                            Html.span [ Attr.class "dv-field-name" ]
                                [ Html.text fieldName ]
                        )
                    |> List.intersperse (viewPunctuation ", ")
                    |> Html.span []
                , viewPunctuation " }"
                ]

        ElmDict entries ->
            viewPunctuation ("Dict (" ++ String.fromInt (List.length entries) ++ ")")

        ElmSet items ->
            viewPunctuation ("Set (" ++ String.fromInt (List.length items) ++ ")")

        ElmCustom name _ ->
            Html.span [ Attr.class "dv-constructor" ]
                [ Html.text (name ++ " ...") ]

        ElmTuple _ ->
            viewPunctuation "(...)"

        _ ->
            Html.text ""
