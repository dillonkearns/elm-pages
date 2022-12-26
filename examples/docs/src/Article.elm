module Article exposing (..)

import Cloudinary
import DataSource
import DataSource.File as File
import DataSource.Glob as Glob
import Date exposing (Date)
import Json.Decode as Decode exposing (Decoder)
import Pages.Url exposing (Url)
import Route


type alias BlogPost =
    { filePath : String
    , slug : String
    }


blogPostsGlob : DataSource.DataSource error (List { filePath : String, slug : String })
blogPostsGlob =
    Glob.succeed BlogPost
        |> Glob.captureFilePath
        |> Glob.match (Glob.literal "content/blog/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
        |> Glob.toDataSource


allMetadata : DataSource.DataSource (File.FileReadError Decode.Error) (List ( Route.Route, ArticleMetadata ))
allMetadata =
    blogPostsGlob
        |> DataSource.map
            (\paths ->
                paths
                    |> List.map
                        (\{ filePath, slug } ->
                            DataSource.map2 Tuple.pair
                                (DataSource.succeed <| Route.Blog__Slug_ { slug = slug })
                                (File.onlyFrontmatter frontmatterDecoder filePath)
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
        |> DataSource.map
            (List.sortBy
                (\( route, metadata ) -> -(Date.toRataDie metadata.published))
            )


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , image : Url
    , draft : Bool
    }


frontmatterDecoder : Decoder ArticleMetadata
frontmatterDecoder =
    Decode.map5 ArticleMetadata
        (Decode.field "title" Decode.string)
        (Decode.field "description" Decode.string)
        (Decode.field "published"
            (Decode.string
                |> Decode.andThen
                    (\isoString ->
                        case Date.fromIsoString isoString of
                            Ok date ->
                                Decode.succeed date

                            Err error ->
                                Decode.fail error
                    )
            )
        )
        (Decode.field "image" imageDecoder)
        (Decode.field "draft" Decode.bool
            |> Decode.maybe
            |> Decode.map (Maybe.withDefault False)
        )


imageDecoder : Decoder Url
imageDecoder =
    Decode.string
        |> Decode.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)
