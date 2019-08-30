module RawContent exposing (content)

import Dict exposing (Dict)


content : List ( List String, { extension: String, frontMatter : String, body : Maybe String } )
content =
    [ 
  ( ["blog", "types-over-conventions"]
    , { frontMatter = """{"author":"Dillon Kearns","title":"Types Over Conventions"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["docs", "directory-structure"]
    , { frontMatter = """{"title":"Directory Structure","type":"doc"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["docs"]
    , { frontMatter = """{"title":"Quick Start","type":"doc"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( []
    , { frontMatter = """{"title":"elm-pages - a statically typed site generator"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["markdown"]
    , { frontMatter = """{"title":"Hello from markdown! 👋"}
""" , body = Nothing
    , extension = "md"
    } )
  
    ]
    