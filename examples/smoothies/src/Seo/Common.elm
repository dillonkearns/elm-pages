module Seo.Common exposing (tags)

import Head exposing (Tag)


tags : List Tag
tags =
    [ Head.metaName "description" (Head.raw "Browse our refreshing blended beverages!")
    ]
