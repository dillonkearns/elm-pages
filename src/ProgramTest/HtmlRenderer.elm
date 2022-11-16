module ProgramTest.HtmlRenderer exposing (render)

import ProgramTest.HtmlHighlighter as HtmlHighlighter exposing (Node(..))


render : (String -> String) -> Int -> List HtmlHighlighter.Node -> String
render colorHidden indent nodes =
    case nodes of
        [] ->
            ""

        (Text text) :: rest ->
            case String.trim (String.replace "\n" " " text) of
                "" ->
                    render colorHidden indent rest

                trimmed ->
                    String.repeat indent " " ++ trimmed ++ "\n" ++ render colorHidden indent rest

        (Comment text) :: rest ->
            String.repeat indent " " ++ "<!--" ++ text ++ "-->\n" ++ render colorHidden indent rest

        (Element tag attrs []) :: rest ->
            String.repeat indent " "
                ++ "<"
                ++ tag
                ++ renderAttrs attrs
                ++ "></"
                ++ tag
                ++ ">\n"
                ++ render colorHidden indent rest

        (Element tag attrs children) :: rest ->
            String.repeat indent " "
                ++ "<"
                ++ tag
                ++ renderAttrs attrs
                ++ ">\n"
                ++ render colorHidden (indent + 4) children
                ++ String.repeat indent " "
                ++ "</"
                ++ tag
                ++ ">\n"
                ++ render colorHidden indent rest

        (Hidden short) :: rest ->
            String.repeat indent " " ++ colorHidden short ++ "\n" ++ render colorHidden indent rest


renderAttrs : List HtmlHighlighter.Attribute -> String
renderAttrs attrs =
    case attrs of
        [] ->
            ""

        some ->
            " " ++ String.join " " (List.map renderAttr some)


renderAttr : ( String, String ) -> String
renderAttr ( name, value ) =
    case ( name, value ) of
        ( "htmlfor", _ ) ->
            "for=\"" ++ value ++ "\""

        ( _, "true" ) ->
            name ++ "=true"

        ( _, "false" ) ->
            name ++ "=false"

        _ ->
            name ++ "=\"" ++ value ++ "\""
