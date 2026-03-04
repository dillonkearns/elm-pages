module FilePath exposing
    ( FilePath
    , fromString, relative, absolute
    , toString
    , segments
    , append, join
    , dirname, filename, filenameWithoutExtension, extension
    , relativeTo
    , resolve
    )

{-| Cross-platform file path utilities for `BackendTask.File` and `Pages.Script`.

The representation is opaque so we can evolve path behavior over time without exposing
implementation details.

@docs FilePath

@docs fromString, relative, absolute

@docs toString

@docs segments

@docs append, join

@docs dirname, filename, filenameWithoutExtension, extension

@docs relativeTo

@docs resolve

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Char
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode


{-| Opaque file path type.
-}
type FilePath
    = FilePath String


{-| Build a path from a string. Accepts both `/` and `\\` separators.

This normalizes the path to a stable representation:

  - Converts `\\` to `/`
  - Collapses duplicate separators
  - Removes `.` segments
  - Resolves `..` segments when possible
  - Removes trailing separators (except for roots)

It accepts both relative and absolute paths.
-}
fromString : String -> FilePath
fromString rawPath =
    FilePath
        (rawPath
            |> normalizeSeparators
            |> FilePath
            |> parse
            |> render
        )


{-| Build a relative path from segments.

    FilePath.relative [ "src", "Main.elm" ]
        |> FilePath.toString
    --> "src/Main.elm"

-}
relative : List String -> FilePath
relative pathSegments =
    pathSegments
        |> List.filter (\segment_ -> segment_ /= "")
        |> String.join "/"
        |> (\joined ->
                if joined == "" then
                    FilePath "."

                else
                    FilePath joined
           )


{-| Build an absolute path from segments.

    FilePath.absolute [ "usr", "bin" ]
        |> FilePath.toString
    --> "/usr/bin"

-}
absolute : List String -> FilePath
absolute pathSegments =
    pathSegments
        |> List.filter (\segment_ -> segment_ /= "")
        |> String.join "/"
        |> (\joined -> FilePath ("/" ++ joined))


{-| Convert a path to a string. Uses `/` separators.
-}
toString : FilePath -> String
toString (FilePath rawPath) =
    rawPath



{-| Return path segments without root markers.
-}
segments : FilePath -> List String
segments filePath =
    (parse filePath).pathSegments


{-| Append a path to a base path.

If `nextPath` has a root marker (absolute path, UNC path, or drive prefix), it replaces
the base path.

-}
append : FilePath -> FilePath -> FilePath
append basePath nextPath =
    let
        nextParsed : ParsedPath
        nextParsed =
            parse nextPath
    in
    if nextParsed.root /= "" then
        nextPath

    else if List.isEmpty nextParsed.pathSegments then
        basePath

    else
        let
            baseParsed : ParsedPath
            baseParsed =
                parse basePath
        in
        FilePath
            (render
                { root = baseParsed.root
                , pathSegments =
                    normalizePathSegments
                        (isAbsoluteRoot baseParsed.root)
                        (baseParsed.pathSegments ++ nextParsed.pathSegments)
                }
            )


{-| Join many paths from left to right.
-}
join : List FilePath -> FilePath
join paths =
    case paths of
        [] ->
            FilePath "."

        firstPath :: restPaths ->
            List.foldl (\nextPath basePath -> append basePath nextPath) firstPath restPaths


{-| Parent directory of a path.
-}
dirname : FilePath -> Maybe FilePath
dirname filePath =
    let
        parsed : ParsedPath
        parsed =
            parse filePath
    in
    case List.reverse parsed.pathSegments of
        [] ->
            if parsed.root == "" then
                Nothing

            else
                Just (FilePath parsed.root)

        _ :: parentSegmentsReversed ->
            let
                parentSegments : List String
                parentSegments =
                    List.reverse parentSegmentsReversed
            in
            if List.isEmpty parentSegments && parsed.root == "" then
                Nothing

            else
                Just
                    (FilePath
                        (render
                            { root = parsed.root
                            , pathSegments = parentSegments
                            }
                        )
                    )


{-| The final path segment, if any.
-}
filename : FilePath -> Maybe String
filename filePath =
    segments filePath
        |> List.reverse
        |> List.head


{-| Filename without extension.
-}
filenameWithoutExtension : FilePath -> Maybe String
filenameWithoutExtension filePath =
    filename filePath
        |> Maybe.map
            (\name ->
                case extensionFromFilename name of
                    Just ext ->
                        String.dropRight (String.length ext + 1) name

                    Nothing ->
                        name
            )


{-| File extension without the dot.
-}
extension : FilePath -> Maybe String
extension filePath =
    filename filePath
        |> Maybe.andThen extensionFromFilename


{-| Path to `targetPath` relative to `basePath`.

Returns `Nothing` when roots differ.

-}
relativeTo : FilePath -> FilePath -> Maybe FilePath
relativeTo basePath targetPath =
    let
        baseParsed : ParsedPath
        baseParsed =
            parse basePath

        targetParsed : ParsedPath
        targetParsed =
            parse targetPath
    in
    if String.toLower baseParsed.root /= String.toLower targetParsed.root then
        Nothing

    else
        let
            { leftRemainder, rightRemainder } =
                dropCommonPrefix baseParsed.pathSegments targetParsed.pathSegments

            relativeSegments : List String
            relativeSegments =
                List.repeat (List.length leftRemainder) ".." ++ rightRemainder
        in
        if List.isEmpty relativeSegments then
            Just (FilePath ".")

        else
            Just (relative relativeSegments)


{-| Resolve a file path to an absolute path using the OS-aware `path.resolve` from Node.js.

Relative paths are resolved against the current working directory.

    import BackendTask exposing (BackendTask)
    import FatalError exposing (FatalError)
    import FilePath

    resolveExample : BackendTask FatalError FilePath
    resolveExample =
        FilePath.fromString "src/Main.elm"
            |> FilePath.resolve

-}
resolve : FilePath -> BackendTask FatalError FilePath
resolve filePath =
    BackendTask.Internal.Request.request
        { name = "resolve-path"
        , body = BackendTask.Http.jsonBody (Encode.string (toString filePath))
        , expect =
            BackendTask.Http.expectJson
                (Decode.string |> Decode.map fromString)
        }


type alias ParsedPath =
    { root : String
    , pathSegments : List String
    }


parse : FilePath -> ParsedPath
parse (FilePath rawPath) =
    let
        normalized : String
        normalized =
            normalizeSeparators rawPath

        ( root, withoutRoot ) =
            splitRoot normalized
    in
    { root = root
    , pathSegments =
        withoutRoot
            |> String.split "/"
            |> normalizePathSegments (isAbsoluteRoot root)
    }


isAbsoluteRoot : String -> Bool
isAbsoluteRoot root =
    case root of
        "/" ->
            True

        "//" ->
            True

        _ ->
            String.endsWith ":/" root


normalizePathSegments : Bool -> List String -> List String
normalizePathSegments hasAbsoluteRoot rawSegments =
    rawSegments
        |> List.foldl
            (\segment_ reversedSegments ->
                case segment_ of
                    "" ->
                        reversedSegments

                    "." ->
                        reversedSegments

                    ".." ->
                        case reversedSegments of
                            top :: rest ->
                                if top == ".." then
                                    if hasAbsoluteRoot then
                                        reversedSegments

                                    else
                                        ".." :: reversedSegments

                                else
                                    rest

                            [] ->
                                if hasAbsoluteRoot then
                                    []

                                else
                                    [ ".." ]

                    _ ->
                        segment_ :: reversedSegments
            )
            []
        |> List.reverse


render : ParsedPath -> String
render parsed =
    let
        joinedSegments : String
        joinedSegments =
            String.join "/" parsed.pathSegments
    in
    if parsed.root == "" then
        if joinedSegments == "" then
            "."

        else
            joinedSegments

    else if joinedSegments == "" then
        parsed.root

    else if String.endsWith ":" parsed.root then
        parsed.root ++ joinedSegments

    else if String.endsWith "/" parsed.root then
        parsed.root ++ joinedSegments

    else
        parsed.root ++ "/" ++ joinedSegments


splitRoot : String -> ( String, String )
splitRoot normalizedPath =
    if String.startsWith "//" normalizedPath then
        ( "//", String.dropLeft 2 normalizedPath )

    else if String.startsWith "/" normalizedPath then
        ( "/", String.dropLeft 1 normalizedPath )

    else
        case driveRoot normalizedPath of
            Just root ->
                if String.endsWith ":/" root then
                    ( root, String.dropLeft 3 normalizedPath )

                else
                    ( root, String.dropLeft 2 normalizedPath )

            Nothing ->
                ( "", normalizedPath )


driveRoot : String -> Maybe String
driveRoot pathString =
    case String.uncons pathString of
        Just ( firstChar, restAfterDrive ) ->
            case String.uncons restAfterDrive of
                Just ( ':', restAfterColon ) ->
                    if Char.isAlpha firstChar then
                        let
                            drivePrefix : String
                            drivePrefix =
                                String.fromChar firstChar ++ ":"
                        in
                        if String.startsWith "/" restAfterColon then
                            Just (drivePrefix ++ "/")

                        else
                            Just drivePrefix

                    else
                        Nothing

                _ ->
                    Nothing

        Nothing ->
            Nothing


normalizeSeparators : String -> String
normalizeSeparators rawPath =
    rawPath
        |> String.map
            (\char ->
                if char == '\\' then
                    '/'

                else
                    char
            )


extensionFromFilename : String -> Maybe String
extensionFromFilename name =
    case List.reverse (String.split "." name) of
        ext :: rest ->
            if List.isEmpty rest || ext == "" || String.join "." (List.reverse rest) == "" then
                Nothing

            else
                Just ext

        [] ->
            Nothing


dropCommonPrefix :
    List String
    -> List String
    -> { leftRemainder : List String, rightRemainder : List String }
dropCommonPrefix left right =
    case ( left, right ) of
        ( leftHead :: leftTail, rightHead :: rightTail ) ->
            if leftHead == rightHead then
                dropCommonPrefix leftTail rightTail

            else
                { leftRemainder = left, rightRemainder = right }

        _ ->
            { leftRemainder = left, rightRemainder = right }
