module Test.Html.Internal.ElmHtml.ToString exposing
    ( nodeRecordToString, nodeToString, nodeToStringWithOptions
    , FormatOptions, defaultFormatOptions
    )

{-| Convert ElmHtml to string.

@docs nodeRecordToString, nodeToString, nodeToStringWithOptions

@docs FormatOptions, defaultFormatOptions

-}

import Dict
import String
import Test.Html.Internal.ElmHtml.InternalTypes exposing (..)


{-| Formatting options to be used for converting to string
-}
type alias FormatOptions =
    { indent : Int
    , newLines : Bool
    }


{-| default formatting options
-}
defaultFormatOptions : FormatOptions
defaultFormatOptions =
    { indent = 0
    , newLines = False
    }


nodeToLines : ElementKind -> FormatOptions -> ElmHtml msg -> List String
nodeToLines kind options nodeType =
    case nodeType of
        TextTag { text } ->
            [ escapeRawText kind text ]

        NodeEntry record ->
            nodeRecordToString options record

        CustomNode record ->
            []

        MarkdownNode record ->
            [ record.model.markdown ]

        NoOp ->
            []


{-| Convert a given html node to a string based on the type
-}
nodeToString : ElmHtml msg -> String
nodeToString =
    nodeToStringWithOptions defaultFormatOptions


{-| same as nodeToString, but with options
-}
nodeToStringWithOptions : FormatOptions -> ElmHtml msg -> String
nodeToStringWithOptions options =
    nodeToLines RawTextElements options
        >> String.join
            (if options.newLines then
                "\n"

             else
                ""
            )


{-| Convert a node record to a string. This basically takes the tag name, then
pulls all the facts into tag declaration, then goes through the children and
nests them under this one
-}
nodeRecordToString : FormatOptions -> NodeRecord msg -> List String
nodeRecordToString options { tag, children, facts } =
    let
        openTag : List (Maybe String) -> String
        openTag extras =
            let
                trimmedExtras =
                    List.filterMap (\x -> x) extras
                        |> List.map String.trim
                        |> List.filter ((/=) "")

                filling =
                    case trimmedExtras of
                        [] ->
                            ""

                        more ->
                            " " ++ String.join " " more
            in
            "<" ++ tag ++ filling ++ ">"

        closeTag =
            "</" ++ tag ++ ">"

        childrenStrings =
            List.map (nodeToLines (toElementKind tag) options) children
                |> List.concat
                |> List.map ((++) (String.repeat options.indent " "))

        styles =
            case Dict.toList facts.styles of
                [] ->
                    Nothing

                styleValues ->
                    styleValues
                        |> List.map (\( key, value ) -> key ++ ":" ++ value ++ ";")
                        |> String.join ""
                        |> (\styleString -> "style=\"" ++ escapeHtml styleString ++ "\"")
                        |> Just

        classes =
            Dict.get "className" facts.stringAttributes
                |> Maybe.map (\name -> "class=\"" ++ escapeHtml name ++ "\"")

        stringAttributes =
            Dict.filter (\k v -> k /= "className") facts.stringAttributes
                |> Dict.toList
                |> List.filter (\( k, _ ) -> not (isUnsafeName k))
                |> List.map (Tuple.mapFirst propertyToAttributeName)
                |> List.map (\( k, v ) -> k ++ "=\"" ++ escapeHtml v ++ "\"")
                |> String.join " "
                |> Just

        boolAttributes =
            Dict.toList facts.boolAttributes
                |> List.filter (\( k, _ ) -> not (isUnsafeName k))
                |> List.filterMap
                    (\( k, v ) ->
                        if v then
                            Just k

                        else
                            Nothing
                    )
                |> String.join " "
                |> Just
    in
    case toElementKind tag of
        InvalidElements ->
            [ "<!-- invalid element -->" ]

        {- Void elements only have a start tag; end tags must not be
           specified for void elements.
        -}
        VoidElements ->
            [ openTag [ classes, styles, stringAttributes, boolAttributes ] ]

        _ ->
            [ openTag [ classes, styles, stringAttributes, boolAttributes ] ]
                ++ childrenStrings
                ++ [ closeTag ]


{-| <https://github.com/elm/virtual-dom/blob/5a5bcf48720bc7d53461b3cd42a9f19f119c5503/src/Elm/Kernel/VirtualDom.server.js#L196-L201>
-}
propertyToAttributeName : String.String -> String.String
propertyToAttributeName propertyName =
    case propertyName of
        "className" ->
            "class"

        "htmlFor" ->
            "for"

        "httpEquiv" ->
            "http-equiv"

        "acceptCharset" ->
            "accept-charset"

        _ ->
            propertyName


escapeRawText : ElementKind -> String.String -> String.String
escapeRawText kind rawText =
    case kind of
        VoidElements ->
            rawText

        RawTextElements ->
            String.replace "</" "<\\/" rawText

        _ ->
            escapeHtml rawText


escapeHtml : String -> String
escapeHtml rawText =
    {- https://github.com/elm/virtual-dom/blob/5a5bcf48720bc7d53461b3cd42a9f19f119c5503/src/Elm/Kernel/VirtualDom.server.js#L8-L26 -}
    rawText
        |> String.replace "&" "&amp;"
        |> String.replace "<" "&lt;"
        |> String.replace ">" "&gt;"
        |> String.replace "\"" "&quot;"
        |> String.replace "'" "&#039;"
