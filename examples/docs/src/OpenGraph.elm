module OpenGraph exposing (Image, website)

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


type Content
    = Website
        { url : String
        , name : String
        , image : Image
        , description : Maybe String
        }


{-| See <https://ogp.me/#structured>
-}
type alias Image =
    { url : String
    , alt : String
    , dimensions : Maybe { width : Int, height : Int }
    , secureUrl : Maybe String
    }


tagsForImage image =
    [ ( "og:image", Just image.url )
    , ( "og:image:alt", Just image.alt )
    , ( "og:image:width", image.dimensions |> Maybe.map .width |> Maybe.map String.fromInt )
    , ( "og:image:height", image.dimensions |> Maybe.map .height |> Maybe.map String.fromInt )
    ]


tags content =
    case content of
        Website details ->
            tagsForImage details.image
                ++ [ ( "og:type", Just "website" )
                   , ( "og:url", Just details.url )
                   , ( "og:locale", Just "en" )
                   , ( "og:site_name", Just details.name )
                   , ( "og:title", Just details.name )
                   , ( "og:description", details.description )
                   ]
                |> List.filterMap
                    (\( name, maybeContent ) ->
                        maybeContent
                            |> Maybe.map (\metaContent -> Head.metaProperty name metaContent)
                    )
