module ElmHtml.ToElmString exposing
    ( nodeRecordToString, toElmString, toElmStringWithOptions
    , FormatOptions, defaultFormatOptions
    )

{-| Convert ElmHtml to string of Elm code.

@docs nodeRecordToString, toElmString, toElmStringWithOptions

@docs FormatOptions, defaultFormatOptions

-}

import Dict exposing (Dict)
import ElmHtml.InternalTypes exposing (..)
import String


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


nodeToLines : FormatOptions -> ElmHtml msg -> List String
nodeToLines options nodeType =
    case nodeType of
        TextTag { text } ->
            [ "Html.text \"" ++ text ++ "\"" ]

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
toElmString : ElmHtml msg -> String
toElmString =
    toElmStringWithOptions defaultFormatOptions


{-| same as toElmString, but with options
-}
toElmStringWithOptions : FormatOptions -> ElmHtml msg -> String
toElmStringWithOptions options =
    nodeToLines options
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
            "Html." ++ tag ++ " [" ++ filling

        childrenStrings =
            List.map (nodeToLines options) children
                |> List.concat
                |> List.map ((++) (String.repeat options.indent " "))

        styles =
            case Dict.toList facts.styles of
                [] ->
                    Nothing

                stylesList ->
                    stylesList
                        |> List.map (\( key, value ) -> "(\"" ++ key ++ "\",\"" ++ value ++ "\")")
                        |> String.join ", "
                        |> (\styleString -> "Html.Attributes.style [" ++ styleString ++ "]")
                        |> Just

        classes =
            Dict.get "className" facts.stringAttributes
                |> Maybe.map (\name -> "Html.Attributes.class [\"" ++ name ++ "\"]")

        stringAttributes =
            Dict.filter (\k v -> k /= "className") facts.stringAttributes
                |> Dict.toList
                |> List.map (\( k, v ) -> "Html.Attributes." ++ k ++ " \"" ++ v ++ "\"")
                |> String.join ", "
                |> Just

        boolAttributes =
            Dict.toList facts.boolAttributes
                |> List.map (\( k, v ) -> "Html.Attributes.property \"" ++ k ++ "\" <| Json.Encode.bool " ++ (if v then "True" else "False"))
                |> String.join " "
                |> Just
    in
    [ openTag [ classes, styles, stringAttributes, boolAttributes ] ]
        ++ [ " ] "
           , "[ "
           , String.join "" childrenStrings
           , "]"
           ]
