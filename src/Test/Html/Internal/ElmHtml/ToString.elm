module Test.Html.Internal.ElmHtml.ToString exposing
    ( nodeRecordToString, nodeToString, nodeToStringWithOptions
    , FormatOptions, defaultFormatOptions
    )

{-| Convert ElmHtml to string.

@docs nodeRecordToString, nodeToString, nodeToStringWithOptions

@docs FormatOptions, defaultFormatOptions

-}

import Dict
import Regex exposing (Regex)
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
        safeTag =
            noScript tag

        elementKind =
            toElementKind safeTag

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
            "<" ++ safeTag ++ filling ++ ">"

        closeTag =
            "</" ++ safeTag ++ ">"

        childrenStrings =
            List.map (nodeToLines elementKind options) children
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
            Dict.get "className" facts.stringProperties
                |> Maybe.map (noJavaScriptOrHtmlUri >> escapeHtml >> (\name -> "class=\"" ++ name ++ "\""))

        stringAttributes =
            facts.stringAttributes
                |> Dict.toList
                |> List.map (\( k, v ) -> ( noOnOrFormAction k, noJavaScriptOrHtmlUri v ))
                |> List.filter (\( k, _ ) -> not (isUnsafeName k))
                |> List.map (\( k, v ) -> k ++ "=\"" ++ escapeHtml v ++ "\"")
                |> String.join " "
                |> Just

        stringProperties =
            Dict.filter (\k _ -> k /= "className") facts.stringProperties
                |> Dict.toList
                |> List.map (\( k, v ) -> ( noInnerHtmlOrFormAction k, noJavaScriptOrHtmlUri v ))
                |> List.map (\( k, v ) -> ( propertyToAttributeName k, v ))
                |> List.filter (\( k, _ ) -> not (isUnsafeName k))
                |> List.map (\( k, v ) -> k ++ "=\"" ++ escapeHtml v ++ "\"")
                |> String.join " "
                |> Just

        boolProperties =
            Dict.toList facts.boolProperties
                |> List.map (\( k, v ) -> ( noInnerHtmlOrFormAction k, v ))
                |> List.map (\( k, v ) -> ( propertyToAttributeName k, v ))
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
    case elementKind of
        InvalidElements ->
            [ "<!-- invalid element -->" ]

        {- Void elements only have a start tag; end tags must not be
           specified for void elements.
        -}
        VoidElements ->
            [ openTag [ classes, styles, stringAttributes, stringProperties, boolProperties ] ]

        _ ->
            [ openTag [ classes, styles, stringAttributes, stringProperties, boolProperties ] ]
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


noScript : String -> String
noScript tag =
    if String.toLower tag == "script" then
        "p"

    else
        tag


noOnOrFormAction : String -> String
noOnOrFormAction key =
    let
        lowerKey =
            String.toLower key
    in
    if String.startsWith "on" lowerKey || lowerKey == "formaction" then
        "data-" ++ key

    else
        key


noInnerHtmlOrFormAction : String -> String
noInnerHtmlOrFormAction key =
    if key == "innerHTML" || key == "outerHTML" || key == "formAction" then
        "data-" ++ key

    else
        key


noJavaScriptOrHtmlUri : String -> String
noJavaScriptOrHtmlUri value =
    if isJavaScriptOrHtmlUri value then
        ""

    else
        value


isJavaScriptOrHtmlUri : String -> Bool
isJavaScriptOrHtmlUri value =
    Regex.contains javaScriptOrHtmlUriRegex (String.toLower value)


javaScriptOrHtmlUriRegex : Regex
javaScriptOrHtmlUriRegex =
    Regex.fromString "^\\s*(j\\s*a\\s*v\\s*a\\s*s\\s*c\\s*r\\s*i\\s*p\\s*t\\s*:|d\\s*a\\s*t\\s*a\\s*:\\s*t\\s*e\\s*x\\s*t\\s*\\/\\s*h\\s*t\\s*m\\s*l\\s*(,|;))"
        |> Maybe.withDefault Regex.never


escapeRawText : ElementKind -> String.String -> String.String
escapeRawText kind rawText =
    case kind of
        VoidElements ->
            rawText

        RawTextElements ->
            {- Prevent closing tag injection in raw text elements (e.g. <style>).
               In pre-rendered HTML, </style> in the text content would cause the
               browser to close the tag early. Inserting a backslash between < and /
               prevents the HTML parser from recognizing it as a closing tag, since
               the parser requires </ (not <\) to start an end tag. This doesn't
               affect CSS validity since </ is already invalid CSS.
            -}
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
