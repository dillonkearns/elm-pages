module Pages.StaticFile exposing (body, frontmatter, glob, rawFile, request)

{-|

@docs body, frontmatter, glob, rawFile, request

-}

import DataSource
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
request : String -> Decoder a -> DataSource.Request a
request filePath =
    DataSource.get (Secrets.succeed <| "file://" ++ filePath)


{-| -}
glob : String -> DataSource.Request (List String)
glob pattern =
    DataSource.get (Secrets.succeed <| "glob://" ++ pattern)
        (OptimizedDecoder.list OptimizedDecoder.string)
