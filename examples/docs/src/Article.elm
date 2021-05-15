module Article exposing (..)

import Cloudinary
import DataSource
import DataSource.File as StaticFile
import DataSource.Glob as Glob
import Date exposing (Date)
import OptimizedDecoder
import Pages.ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Route


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
        |> Glob.toDataSource


allMetadata : DataSource.DataSource (List ( Route.Route, ArticleMetadata ))
allMetadata =
    --StaticFile.glob "content/blog/*.md"
    blogPostsGlob
        |> DataSource.map
            (\paths ->
                paths
                    |> List.map
                        (\{ filePath, slug } ->
                            DataSource.map2 Tuple.pair
                                (DataSource.succeed <| Route.Blog__Slug_ { slug = slug })
                                (StaticFile.request filePath (StaticFile.frontmatter frontmatterDecoder))
                        )
            )
        |> DataSource.resolve
        |> DataSource.map
            (\articles ->
                articles
                    |> List.filterMap
                        (\( route, metadata ) ->
                            if metadata.draft then
                                Nothing

                            else
                                Just ( route, metadata )
                        )
            )


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
