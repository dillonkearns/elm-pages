module OpenGraph exposing (Image, article, website)

{-| <https://ogp.me/#>
-}

import Pages.Head as Head


{-| <https://ogp.me/#type_website>
-}
website :
    { url : String
    , name : String
    , image : Image
    , description : Maybe String
    }
    -> List Head.Tag
website details =
    Website details
        |> tags


{-| See <https://ogp.me/#type_article>
-}
article details =
    Article details
        |> tags


type Content
    = Website
        { url : String
        , name : String
        , image : Image
        , description : Maybe String
        }
    | Article
        { image : Image
        , name : String
        , url : String
        , description : String
        , tags : List String
        , section : Maybe String
        , siteName : String
        }


{-| See <https://ogp.me/#structured>
-}
type alias Image =
    { url : String
    , alt : String
    , dimensions : Maybe { width : Int, height : Int }
    , secureUrl : Maybe String
    }


tagsForImage : Image -> List ( String, Maybe String )
tagsForImage image =
    [ ( "og:image", Just image.url )
    , ( "og:image:alt", Just image.alt )
    , ( "og:image:width", image.dimensions |> Maybe.map .width |> Maybe.map String.fromInt )
    , ( "og:image:height", image.dimensions |> Maybe.map .height |> Maybe.map String.fromInt )
    ]


tags : Content -> List Head.Tag
tags content =
    (case content of
        Website details ->
            tagsForImage details.image
                ++ [ ( "og:type", Just "website" )
                   , ( "og:url", Just details.url )
                   , ( "og:locale", Just "en" )
                   , ( "og:site_name", Just details.name )
                   , ( "og:title", Just details.name )
                   , ( "og:description", details.description )
                   ]

        Article details ->
            tagsForImage details.image
                ++ [ ( "og:type", Just "article" )
                   , ( "og:url", Just details.url )
                   , ( "og:locale", Just "en" ) -- TODO make locale configurable
                   , ( "og:site_name", Just details.siteName )
                   , ( "og:title", Just details.name )
                   , ( "og:description", Just details.description )
                   , ( "article:section", details.section )
                   ]
                ++ List.map
                    (\tag -> ( "article:tag", tag |> Just ))
                    details.tags
    )
        |> List.filterMap
            (\( name, maybeContent ) ->
                maybeContent
                    |> Maybe.map (\metaContent -> Head.metaProperty name metaContent)
            )
