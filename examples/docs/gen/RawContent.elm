module RawContent exposing (content)

import Dict exposing (Dict)


content : List ( List String, { extension: String, frontMatter : String, body : Maybe String } )
content =
    [ 
  ( ["markdown"]
    , { frontMatter = """{"title":"Hello from markdown! 👋"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["about"]
    , { frontMatter = """
|> Article
    title = How I Learned /elm-markup/
    description = How I learned to use elm-markup.

""" , body = Nothing
    , extension = "emu"
    } )
  ,
  ( ["docs", "file-structure"]
    , { frontMatter = """
|> Doc
    title = File Structure
""" , body = Nothing
    , extension = "emu"
    } )
  ,
  ( ["docs"]
    , { frontMatter = """
|> Doc
    title = Quick Start
""" , body = Nothing
    , extension = "emu"
    } )
  ,
  ( []
    , { frontMatter = """
|> Page
    title = elm-pages - a statically typed site generator

""" , body = Nothing
    , extension = "emu"
    } )
  
    ]
    