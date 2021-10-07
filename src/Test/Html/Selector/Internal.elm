module Test.Html.Selector.Internal exposing (Selector(..), hasAll, namedAttr, namedBoolAttr, query, queryAll, queryAllChildren, selectorToString, styleToString)

import Test.Html.Internal.ElmHtml.InternalTypes exposing (ElmHtml)
import Test.Html.Internal.ElmHtml.Query as ElmHtmlQuery


type Selector
    = All (List Selector)
    | Classes (List String)
    | Class String
    | Attribute { name : String, value : String }
    | BoolAttribute { name : String, value : Bool }
    | Style { key : String, value : String }
    | Tag String
    | Text String
    | Containing (List Selector)
    | Invalid


selectorToString : Selector -> String
selectorToString criteria =
    let
        quoteString s =
            "\"" ++ s ++ "\""

        boolToString b =
            case b of
                True ->
                    "True"

                False ->
                    "False"
    in
    case criteria of
        All list ->
            list
                |> List.map selectorToString
                |> String.join " "

        Classes list ->
            "classes " ++ quoteString (String.join " " list)

        Class class ->
            "class " ++ quoteString class

        Attribute { name, value } ->
            "attribute "
                ++ quoteString name
                ++ " "
                ++ quoteString value

        BoolAttribute { name, value } ->
            "attribute "
                ++ quoteString name
                ++ " "
                ++ boolToString value

        Style style ->
            "styles " ++ styleToString style

        Tag name ->
            "tag " ++ quoteString name

        Text text ->
            "text " ++ quoteString text

        Containing list ->
            let
                selectors =
                    list
                        |> List.map selectorToString
                        |> String.join ", "
            in
            "containing [ " ++ selectors ++ " ] "

        Invalid ->
            "invalid"


styleToString : { key : String, value : String } -> String
styleToString { key, value } =
    key ++ ":" ++ value


hasAll : List Selector -> List (ElmHtml msg) -> Bool
hasAll selectors elems =
    case selectors of
        [] ->
            True

        selector :: rest ->
            if List.isEmpty (queryAll [ selector ] elems) then
                False

            else
                hasAll rest elems


queryAll : List Selector -> List (ElmHtml msg) -> List (ElmHtml msg)
queryAll selectors list =
    case selectors of
        [] ->
            list

        selector :: rest ->
            query ElmHtmlQuery.query queryAll selector list
                |> queryAll rest


queryAllChildren : List Selector -> List (ElmHtml msg) -> List (ElmHtml msg)
queryAllChildren selectors list =
    case selectors of
        [] ->
            list

        selector :: rest ->
            query ElmHtmlQuery.queryChildren queryAllChildren selector list
                |> queryAllChildren rest


query :
    (ElmHtmlQuery.Selector -> ElmHtml msg -> List (ElmHtml msg))
    -> (List Selector -> List (ElmHtml msg) -> List (ElmHtml msg))
    -> Selector
    -> List (ElmHtml msg)
    -> List (ElmHtml msg)
query fn fnAll selector list =
    case list of
        [] ->
            list

        elems ->
            case selector of
                All selectors ->
                    fnAll selectors elems

                Classes classes ->
                    List.concatMap (fn (ElmHtmlQuery.ClassList classes)) elems

                Class class ->
                    List.concatMap (fn (ElmHtmlQuery.ClassList [ class ])) elems

                Attribute { name, value } ->
                    List.concatMap (fn (ElmHtmlQuery.Attribute name value)) elems

                BoolAttribute { name, value } ->
                    List.concatMap (fn (ElmHtmlQuery.BoolAttribute name value)) elems

                Style style ->
                    List.concatMap (fn (ElmHtmlQuery.Style style)) elems

                Tag name ->
                    List.concatMap (fn (ElmHtmlQuery.Tag name)) elems

                Text text ->
                    List.concatMap (fn (ElmHtmlQuery.ContainsText text)) elems

                Containing selectors ->
                    let
                        anyDescendantsMatch elem =
                            case ElmHtmlQuery.getChildren elem of
                                [] ->
                                    -- We have no children;
                                    -- no descendants can possibly match.
                                    False

                                children ->
                                    case query fn fnAll (All selectors) children of
                                        [] ->
                                            -- None of our children matched,
                                            -- but their descendants might!
                                            List.any anyDescendantsMatch children

                                        _ :: _ ->
                                            -- At least one child matched. Yay!
                                            True
                    in
                    List.filter anyDescendantsMatch elems

                Invalid ->
                    []


namedAttr : String -> String -> Selector
namedAttr name value =
    Attribute
        { name = name
        , value = value
        }


namedBoolAttr : String -> Bool -> Selector
namedBoolAttr name value =
    BoolAttribute
        { name = name
        , value = value
        }
