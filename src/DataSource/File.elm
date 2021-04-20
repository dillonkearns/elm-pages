module DataSource.File exposing (body, frontmatter, glob, rawFile, request)

{-|

@docs body, frontmatter, glob, rawFile, request

-}

import DataSource
import DataSource.Http
import OptimizedDecoder exposing (Decoder)
import Secrets


{-| -}
frontmatter : Decoder frontmatter -> Decoder frontmatter
frontmatter frontmatterDecoder =
    OptimizedDecoder.field "parsedFrontmatter" frontmatterDecoder


{-| -}
rawFile : Decoder String
rawFile =
    OptimizedDecoder.field "rawFile" OptimizedDecoder.string


{-| -}
body : Decoder String
body =
    OptimizedDecoder.field "withoutFrontmatter" OptimizedDecoder.string


{-| -}
request : String -> Decoder a -> DataSource.DataSource a
request filePath =
    DataSource.Http.get (Secrets.succeed <| "file://" ++ filePath)


{-| -}
glob : String -> DataSource.DataSource (List String)
glob pattern =
    DataSource.Http.get (Secrets.succeed <| "glob://" ++ pattern)
        (OptimizedDecoder.list OptimizedDecoder.string)
