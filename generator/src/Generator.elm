module Generator exposing (generate)

import String.Interpolate exposing (interpolate)


generate =
    interpolate """

pages : List ( List String, String )
pages =
    [ ( [ {0} ]
      , \"\"\"|> Article
    author = Dillon Kearns
    title = Home Page
    tags = software other
    description =
        How I learned to use elm-markup.

This is the home page.
\"\"\"
      ) ]
posts :
    Result (List Mark.Error.Error)
        (List
            ( List String
            , { body : List (Element msg)
              , metadata : MarkParser.Metadata msg
              }
            )
        )
posts =
    [ ( [ "articles", "tiny-steps" ]
      , \"\"\"|> Article
    author = Dillon Kearns
    title = Tiny Steps
    tags = software other
    description =
        How I learned to use elm-markup.

  Here is an article.
  \"\"\"
      )
"""
        [ "\"\"" ]
