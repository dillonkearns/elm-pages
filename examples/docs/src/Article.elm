module Article exposing (..)

import Cloudinary
import DataSource
import DataSource.File as StaticFile
import Date exposing (Date)
import Element exposing (Element)
import Glob
import OptimizedDecoder
import Pages.ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)


type alias BlogPost =
    { filePath : String
    , slug : String
    }


blogPostsGlob : DataSource.DataSource (List { filePath : String, slug : String })
blogPostsGlob =
    Glob.succeed BlogPost
        |> Glob.capture Glob.fullFilePath
        |> Glob.ignore (Glob.literal "content/blog/")
        |> Glob.capture Glob.wildcard
        |> Glob.ignore (Glob.literal ".md")
        |> Glob.toStaticHttp


allMetadata : DataSource.DataSource (List ( PagePath, ArticleMetadata ))
allMetadata =
    --StaticFile.glob "content/blog/*.md"
    blogPostsGlob
        |> DataSource.map
            (\paths ->
                paths
                    |> List.map
                        (\{ filePath, slug } ->
                            DataSource.map2 Tuple.pair
                                (DataSource.succeed <| "blog/" ++ slug)
                                (StaticFile.request filePath (StaticFile.frontmatter frontmatterDecoder))
                        )
            )
        |> DataSource.resolve
        |> DataSource.map
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


fileRequest : String -> DataSource.DataSource ArticleMetadata
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
    , image : ImagePath
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


imageDecoder : OptimizedDecoder.Decoder ImagePath
imageDecoder =
    OptimizedDecoder.string
        |> OptimizedDecoder.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)
