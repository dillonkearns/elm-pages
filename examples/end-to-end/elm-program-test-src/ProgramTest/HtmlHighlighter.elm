module ProgramTest.HtmlHighlighter exposing (Attribute, Node(..), NodeF(..), fold, foldWithOriginal, highlight, isNonHiddenElement)

import Html.Parser


type NodeF a
    = TextF String
    | ElementF String (List Attribute) (List a)
    | CommentF String


type alias Attribute =
    ( String, String )


fold : (NodeF a -> a) -> Html.Parser.Node -> a
fold f node =
    case node of
        Html.Parser.Text text ->
            f (TextF text)

        Html.Parser.Element tag attrs children ->
            f (ElementF tag attrs (List.map (fold f) children))

        Html.Parser.Comment string ->
            f (CommentF string)


foldWithOriginal : (NodeF ( Html.Parser.Node, a ) -> a) -> Html.Parser.Node -> a
foldWithOriginal f node =
    case node of
        Html.Parser.Text text ->
            f (TextF text)

        Html.Parser.Element tag attrs children ->
            f (ElementF tag attrs (List.map (\child -> ( child, foldWithOriginal f child )) children))

        Html.Parser.Comment string ->
            f (CommentF string)


type Node
    = Text String
    | Element String (List Attribute) (List Node)
    | Comment String
    | Hidden String


highlight : (String -> List Attribute -> List Html.Parser.Node -> Bool) -> Html.Parser.Node -> Node
highlight predicate =
    foldWithOriginal <|
        \node ->
            case node of
                TextF text ->
                    Text text

                ElementF tag attrs children ->
                    let
                        foldedChildren =
                            List.map Tuple.second children
                    in
                    if predicate tag attrs (List.map Tuple.first children) || List.any isNonHiddenElement foldedChildren then
                        Element tag attrs foldedChildren

                    else
                        let
                            bestId =
                                List.concatMap identity
                                    [ List.filter (Tuple.first >> (==) "id") attrs
                                    , List.filter (Tuple.first >> (==) "name") attrs
                                    , List.filter (Tuple.first >> (==) "class") attrs
                                    ]
                                    |> List.head
                                    |> Maybe.map (\( name, value ) -> " " ++ name ++ "=\"" ++ value ++ "\"")
                                    |> Maybe.withDefault ""

                            bestContent =
                                case foldedChildren of
                                    [] ->
                                        ""

                                    [ Text single ] ->
                                        truncate 15 (String.trim single)

                                    _ ->
                                        "..."
                        in
                        Hidden ("<" ++ tag ++ bestId ++ ">" ++ bestContent ++ "</" ++ tag ++ ">")

                CommentF string ->
                    Comment string


isNonHiddenElement : Node -> Bool
isNonHiddenElement node =
    case node of
        Text _ ->
            False

        Element _ _ _ ->
            True

        Comment _ ->
            False

        Hidden _ ->
            False


truncate : Int -> String -> String
truncate max input =
    if String.length input < max - 3 then
        input

    else
        String.left (max - 3) input ++ "..."
