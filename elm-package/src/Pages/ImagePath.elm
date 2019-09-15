module Pages.ImagePath exposing (ImagePath, build, external, toString)

{-| This module is analgous to `Pages.PagePath`, except it represents an
Image Path rather than a Page Path. Rather than copy-pasting those docs, I'll
note the differences here. See the `Pages.PagePath` docs for more background.


## Record-based `PagePath` lookup

You can lookup a specific static image path based on its path using the record-based lookup:

    Pages.images

This gives you a record, based on all the files in your local
`images` directory, that lets you look paths up like so:

    import Pages
    import Pages.ImagePath as ImagePath exposing (ImagePath)

    homePath : ImagePath Pages.PathKey
    homePath =
        Pages.pages.index

    -- ImagePath.toString homePath
    -- => "/"

or

    import Pages
    import Pages.ImagePath as ImagePath exposing (ImagePath)

    dillonProfilePhoto : ImagePath Pages.PathKey
    dillonProfilePhoto =
        Pages.images.profilePhotos.dillon

    -- ImagePath.toString helloWorldPostPath
    -- => "/images/profile-photos/dillon.jpg"

-}


type ImagePath key
    = Internal (List String)
    | External String


toString : ImagePath key -> String
toString path =
    case path of
        Internal rawPath ->
            "/"
                ++ (rawPath |> String.join "/")

        External url ->
            url


build : key -> List String -> ImagePath key
build key path =
    Internal path


external : String -> ImagePath key
external url =
    External url
