module Pages.StaticFile exposing (body, frontmatter, glob, rawFile, request)

import OptimizedDecoder exposing (Decoder)
import Pages.StaticHttp as StaticHttp
import Secrets


frontmatter : Decoder frontmatter -> Decoder frontmatter
frontmatter frontmatterDecoder =
    OptimizedDecoder.field "parsedFrontmatter" frontmatterDecoder


rawFile : Decoder String
rawFile =
    OptimizedDecoder.field "rawFile" OptimizedDecoder.string


body : Decoder String
body =
    OptimizedDecoder.field "withoutFrontmatter" OptimizedDecoder.string


request : String -> Decoder a -> StaticHttp.Request a
request filePath =
    StaticHttp.get (Secrets.succeed <| "file://" ++ filePath)


glob : String -> StaticHttp.Request (List String)
glob pattern =
    StaticHttp.get (Secrets.succeed <| "glob://" ++ pattern)
        (OptimizedDecoder.list OptimizedDecoder.string)
