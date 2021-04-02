module Article exposing (..)

import Cloudinary
import Date exposing (Date)
import Element exposing (Element)
import Glob
import MarkdownRenderer
import OptimizedDecoder
import Pages
import Pages.ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticFile as StaticFile
import Pages.StaticHttp as StaticHttp


type alias BlogPost =
    { filePath : String
    , slug : String
    }


blogPostsGlob : StaticHttp.Request (List { filePath : String, slug : String })
blogPostsGlob =
    Glob.succeed BlogPost
        |> Glob.keep Glob.fullFilePath
        |> Glob.drop (Glob.literal "content/blog/")
        |> Glob.keep Glob.wildcard
        |> Glob.drop (Glob.literal ".md")
        |> Glob.toStaticHttp


allMetadata : StaticHttp.Request (List ( PagePath Pages.PathKey, ArticleMetadata ))
allMetadata =
    --StaticFile.glob "content/blog/*.md"
    blogPostsGlob
        |> StaticHttp.map
            (\paths ->
                paths
                    |> List.filter (\{ slug } -> slug /= "index")
                    |> List.map
                        (\{ filePath, slug } ->
                            StaticHttp.map2 Tuple.pair
                                (StaticHttp.succeed <| "blog/" ++ slug)
                                (StaticFile.request filePath (StaticFile.frontmatter frontmatterDecoder))
                        )
            )
        |> StaticHttp.resolve
        |> StaticHttp.map
            (\articles ->
                articles
                    |> List.filterMap
                        (\( path, metadata ) ->
                            if metadata.draft then
                                Nothing

                            else
                                Just
                                    ( path |> PagePath.external
                                    , metadata
                                    )
                        )
            )


type alias DataFromFile msg =
    { body : List (Element msg)
    , metadata : ArticleMetadata
    }



--fileRequest : String -> StaticHttp.Request (DataFromFile msg)


fileRequest : String -> StaticHttp.Request ArticleMetadata
fileRequest filePath =
    StaticFile.request
        --"content/blog/extensible-markdown-parsing-in-elm.md"
        filePath
        --(OptimizedDecoder.map2 DataFromFile
        --    (StaticFile.body
        --        |> OptimizedDecoder.andThen
        --            (\rawBody ->
        --                case
        --                    rawBody
        --                        |> MarkdownRenderer.view
        --                        |> Result.map Tuple.second
        --                of
        --                    Ok renderedBody ->
        --                        OptimizedDecoder.succeed renderedBody
        --
        --                    Err error ->
        --                        OptimizedDecoder.fail error
        --            )
        --    )
        (StaticFile.frontmatter frontmatterDecoder)



--)


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , image : ImagePath Pages.PathKey
    , draft : Bool
    }


frontmatterDecoder : OptimizedDecoder.Decoder ArticleMetadata
frontmatterDecoder =
    OptimizedDecoder.map5 ArticleMetadata
        (OptimizedDecoder.field "title" OptimizedDecoder.string)
        (OptimizedDecoder.field "description" OptimizedDecoder.string)
        (OptimizedDecoder.field "published"
            (OptimizedDecoder.string
                |> OptimizedDecoder.andThen
                    (\isoString ->
                        case Date.fromIsoString isoString of
                            Ok date ->
                                OptimizedDecoder.succeed date

                            Err error ->
                                OptimizedDecoder.fail error
                    )
            )
        )
        (OptimizedDecoder.field "image" imageDecoder)
        (OptimizedDecoder.field "draft" OptimizedDecoder.bool
            |> OptimizedDecoder.maybe
            |> OptimizedDecoder.map (Maybe.withDefault False)
        )


imageDecoder : OptimizedDecoder.Decoder (ImagePath Pages.PathKey)
imageDecoder =
    OptimizedDecoder.string
        |> OptimizedDecoder.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)
