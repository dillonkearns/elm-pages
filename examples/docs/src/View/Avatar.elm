module View.Avatar exposing (view)

import Element
import Html.Attributes as Attr
import Pages.Path as Path


view author =
    Element.image
        [ Element.width (Element.px 70)
        , Element.htmlAttribute (Attr.class "avatar")
        ]
        { src = Path.toString author.avatar, description = author.name }
