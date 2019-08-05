module OpenGraph exposing (website)

{-| <https://ogp.me/#>
-}

import Pages.Head as Head


{-| <https://ogp.me/#type_website>
-}
website :
    { url : String
    , name : String
    , imageUrl : String
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
        , imageUrl : String
        , description : Maybe String
        }


tags content =
    case content of
        Website details ->
            [ ( "og:type", Just "website" )
            , ( "og:url", Just details.url )
            , ( "og:locale", Just "en" )
            , ( "og:site_name", Just details.name )
            , ( "og:title", Just details.name )
            , ( "og:image", Just details.imageUrl )
            , ( "og:description", details.description )
            ]
                |> List.filterMap
                    (\( name, maybeContent ) ->
                        maybeContent
                            |> Maybe.map (\metaContent -> Head.metaName name metaContent)
                    )
