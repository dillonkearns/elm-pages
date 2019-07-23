module Index exposing (view)

import Element exposing (Element)
import MarkParser


view :
    List
        ( List String
        , { body : List (Element msg)
          , metadata : MarkParser.Metadata msg
          }
        )
    -> Element msg
view posts =
    Element.column [ Element.spacing 20 ]
        (posts
            |> List.map postSummary
        )


postSummary :
    ( List String
    , { body : List (Element msg)
      , metadata : MarkParser.Metadata msg
      }
    )
    -> Element msg
postSummary ( postPath, post ) =
    Element.paragraph [] post.metadata.title
        |> linkToPost postPath


linkToPost : List String -> Element msg -> Element msg
linkToPost postPath content =
    Element.link []
        { url = postUrl postPath, label = content }


postUrl : List String -> String
postUrl postPath =
    "/"
        ++ String.join "/" postPath
