module Head.ResourceHints exposing
    ( CrossOrigin(..)
    , FileType(..)
    , dnsPrefetchLink
    , preconnectLink
    , prefetchLink
    , preloadLink
    )

import Head exposing (ResourceHint(..), Tag, raw, resourceHintLink)


{-| Possible values for resource hint `crossorigin` attribute
-}
type CrossOrigin
    = Anonymous
    | UseCredentials


{-| Possible values for resource hint `as` attribute
-}
type FileType
    = Audio
    | Document
    | Embed
    | Fetch
    | Font
    | Image
    | Object
    | Script
    | Style
    | Track
    | Worker
    | Video


{-| Create a dns-prefetch resource hint.

Instructs the browser to perform DNS lookup for domains that will be needed to load external assets.

See: <https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types/dns-prefetch>

-}
dnsPrefetchLink : String -> Tag
dnsPrefetchLink href =
    resourceHintLink DnsPrefetch href Nothing Nothing


{-| Create a preconnect resource hint

Instructs the browser to establish a connection to a server that will be needed to load external assets.

Example:

    preconnectLink "https://fonts.gstatic.com/" (Just Anonymous)

```html
<link rel="preconnect" href="https://fonts.gstatic.com/" crossorigin>
```

See: <https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types/preconnect>

-}
preconnectLink : String -> Maybe CrossOrigin -> Tag
preconnectLink href =
    resourceHintWithOptionalAttributes Preconnect href Nothing


{-| Create a preload resource hint

Instructs the browser to begin downloading an asset that will be needed immediately.

Useful for preventing request waterfalls for images and css loaded via CSS.

Given the following:

```css
.my-class {
    background-image: url(/images/background.png);
}
```

in an external css file, the browser would normally have to first retrieve and parse the CSS,
_then_ fetch the background image. Adding a prefetch hint for this will cause the browser to
begin downloading the image and css concurrently.

Example:

    preloadLink "/images/background.png" (Just Image) Nothing

```html
<link rel="preload" href="/images/background.png" as="image">
```

See: <https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types/preload>

-}
preloadLink : String -> Maybe FileType -> Maybe CrossOrigin -> Tag
preloadLink =
    resourceHintWithOptionalAttributes Preload


{-| Create a prefetch resource hint

Instructs the browser that an asset will likely be needed during the life of this
page on on a subsequent navigation and to download them with low-priority and cache.

See: <https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types/prefetch>

-}
prefetchLink : String -> Maybe FileType -> Maybe CrossOrigin -> Tag
prefetchLink =
    resourceHintWithOptionalAttributes Prefetch


resourceHintWithOptionalAttributes : ResourceHint -> String -> Maybe FileType -> Maybe CrossOrigin -> Tag
resourceHintWithOptionalAttributes hint href fileType crossOrigin =
    resourceHintLink hint
        href
        (Maybe.map (resourceFileTypeToString >> raw) fileType)
        (Maybe.map (crossOriginToString >> raw) crossOrigin)


crossOriginToString : CrossOrigin -> String
crossOriginToString crossOrigin =
    case crossOrigin of
        Anonymous ->
            "anonymous"

        UseCredentials ->
            "use-credentials"


resourceFileTypeToString : FileType -> String
resourceFileTypeToString fileType =
    case fileType of
        Audio ->
            "audio"

        Document ->
            "document"

        Embed ->
            "embed"

        Fetch ->
            "fetch"

        Font ->
            "font"

        Image ->
            "image"

        Object ->
            "object"

        Script ->
            "script"

        Style ->
            "style"

        Track ->
            "track"

        Worker ->
            "worker"

        Video ->
            "video"
