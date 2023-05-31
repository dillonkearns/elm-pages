module Seo.Common exposing (tags)

import Head exposing (Tag)
import Head.Seo as Seo
import Pages.Url


tags : List Tag
tags =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Ctrl-R Smoothies"
        , image =
            { url = Pages.Url.external "https://images.unsplash.com/photo-1615478503562-ec2d8aa0e24e?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1887"
            , alt = "Ctrl-R Smoothies Logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Browse our refreshing blended beverages!"
        , locale = Nothing
        , title = "Ctrl-R Smoothies"
        }
        |> Seo.website
