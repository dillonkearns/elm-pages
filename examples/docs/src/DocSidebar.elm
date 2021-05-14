module DocSidebar exposing (view)

import Element exposing (Element)
import Element.Border as Border
import Pages.PagePath exposing (PagePath)


view :
    PagePath
    -> Element msg
view currentPage =
    Element.column
        [ Element.spacing 10
        , Border.widthEach { bottom = 0, left = 0, right = 1, top = 0 }
        , Border.color (Element.rgba255 40 80 40 0.4)
        , Element.padding 12
        , Element.height Element.fill
        ]
        []



--(posts
--    |> List.filterMap
--        (\( path, metadata ) ->
--            case metadata of
--                TemplateType.Documentation meta ->
--                    Just ( currentPage == path, path, meta )
--
--                _ ->
--                    Nothing
--        )
--    |> List.map postSummary
--)
