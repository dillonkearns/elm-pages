module FilePath.Internal exposing (isAbsolute)

import Char
import FilePath exposing (FilePath)


{-| Whether this path is absolute. Package-internal only — not exposed to consumers.

Checks the normalized string prefix, which is equivalent to checking the parsed root
since `FilePath.fromString` guarantees consistent formatting:

  - `/...` → POSIX absolute
  - `//...` → UNC absolute
  - `X:/...` → Windows drive absolute

-}
isAbsolute : FilePath -> Bool
isAbsolute filePath =
    let
        str : String
        str =
            FilePath.toString filePath
    in
    String.startsWith "/" str
        || hasAbsoluteDriveRoot str


hasAbsoluteDriveRoot : String -> Bool
hasAbsoluteDriveRoot str =
    case String.uncons str of
        Just ( firstChar, rest ) ->
            Char.isAlpha firstChar && String.startsWith ":/" rest

        Nothing ->
            False
