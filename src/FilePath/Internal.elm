module FilePath.Internal exposing (isAbsolute)

import Char


{-| Whether a path string represents an absolute path. Package-internal only — not
exposed to consumers.

Works on the normalized string form produced by `FilePath.toString`:

  - `/...` → POSIX absolute
  - `//...` → UNC absolute
  - `X:/...` → Windows drive absolute

-}
isAbsolute : String -> Bool
isAbsolute str =
    String.startsWith "/" str
        || hasAbsoluteDriveRoot str


hasAbsoluteDriveRoot : String -> Bool
hasAbsoluteDriveRoot str =
    case String.uncons str of
        Just ( firstChar, rest ) ->
            Char.isAlpha firstChar && String.startsWith ":/" rest

        Nothing ->
            False
