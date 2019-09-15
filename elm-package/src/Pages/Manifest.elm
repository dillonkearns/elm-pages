module Pages.Manifest exposing
    ( Config
    , toJson
    , DisplayMode(..), Orientation(..)
    )

{-| Represents the configuration of a
[web manifest file](https://developer.mozilla.org/en-US/docs/Web/Manifest).

You pass your `Pages.Manifest.Config` record into the `Pages.application` function
(from your generated `Pages.elm` file).

    import Pages
    import Pages.Manifest as Manifest
    import Pages.Manifest.Category
    import Pages.PagePath as PagePath exposing (PagePath)
    import Palette

    manifest : Manifest.Config PagesNew.PathKey
    manifest =
        { backgroundColor = Just Color.white
        , categories = [ Pages.Manifest.Category.education ]
        , displayMode = Manifest.Standalone
        , orientation = Manifest.Portrait
        , description = "elm-pages - A statically typed site generator."
        , iarcRatingId = Nothing
        , name = "elm-pages docs"
        , themeColor = Just Color.white
        , startUrl = Pages.pages.index
        , shortName = Just "elm-pages"
        , sourceIcon = Pages.images.icon
        }

    main : Pages.Program Model Msg Metadata (List (Element Msg))
    main =
        PagesNew.application
            { init = init
            , view = view
            , update = update
            , subscriptions = subscriptions
            , documents = [ markdownDocument ]
            , head = head
            , manifest = manifest
            , canonicalSiteUrl = canonicalSiteUrl
            }

@docs Config


## Functions for use by the generated code (`Pages.elm`)

@docs toJson

-}

import Color exposing (Color)
import Color.Convert
import Json.Encode as Encode
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest.Category as Category exposing (Category)
import Pages.PagePath as PagePath exposing (PagePath)



{- TODO serviceworker https://developer.mozilla.org/en-US/docs/Web/Manifest/serviceworker
   This is mandatory... need to process this in a special way
-}
-- TODO icons https://developer.mozilla.org/en-US/docs/Web/Manifest/icons
-- TODO use language https://developer.mozilla.org/en-US/docs/Web/Manifest/lang


type alias Language =
    { dir : String -- "rtl",
    , lang : String -- "ar" -- TODO should this be an enum? What standard code?
    }


{-| See <https://developer.mozilla.org/en-US/docs/Web/Manifest/display>
-}
type DisplayMode
    = Fullscreen
    | Standalone
    | MinimalUi
    | Browser


{-| <https://developer.mozilla.org/en-US/docs/Web/Manifest/orientation>
-}
type Orientation
    = Any
    | Natural
    | Landscape
    | LandscapePrimary
    | LandscapeSecondary
    | Portrait
    | PortraitPrimary
    | PortraitSecondary


orientationToString : Orientation -> String
orientationToString orientation =
    case orientation of
        Any ->
            "any"

        Natural ->
            "natural"

        Landscape ->
            "landscape"

        LandscapePrimary ->
            "landscape-primary"

        LandscapeSecondary ->
            "landscape-secondary"

        Portrait ->
            "portrait"

        PortraitPrimary ->
            "portrait-primary"

        PortraitSecondary ->
            "portrait-secondary"


{-| Represents a [web app manifest file](https://developer.mozilla.org/en-US/docs/Web/Manifest)
(see above for how to use it).

The `sourceIcon` is used to automatically generate all of the Favicons and manifest
icons of the appropriate sizes (512x512, etc) for Android, iOS, etc. So you just
point at a single image asset and you will have optimized images following all
the best practices!


## Type-safe static paths

The `pathKey` in this type is used to ensure that you are using
known static resources for any internal image or page paths.

  - The `startUrl` is a type-safe `PagePath`, ensuring that any internal links
    are present (not broken links).
  - The `sourceIcon` is a type-safe `ImagePath`, ensuring that any internal images
    are present (not broken images).

-}
type alias Config pathKey =
    { backgroundColor : Maybe Color
    , categories : List Category
    , displayMode : DisplayMode
    , orientation : Orientation
    , description : String
    , iarcRatingId : Maybe String
    , name : String
    , themeColor : Maybe Color

    -- https://developer.mozilla.org/en-US/docs/Web/Manifest/start_url
    , startUrl : PagePath pathKey

    -- https://developer.mozilla.org/en-US/docs/Web/Manifest/short_name
    , shortName : Maybe String
    , sourceIcon : ImagePath pathKey
    }


displayModeToAttribute : DisplayMode -> String
displayModeToAttribute displayMode =
    case displayMode of
        Fullscreen ->
            "fullscreen"

        Standalone ->
            "standalone"

        MinimalUi ->
            "minimal-ui"

        Browser ->
            "browser"


{-| Feel free to use this, but in 99% of cases you won't need it. The generated
code will run this for you to generate your `manifest.json` file automatically!
-}
toJson : Config pathKey -> Encode.Value
toJson config =
    [ ( "sourceIcon"
      , config.sourceIcon
            |> ImagePath.toString
            |> Encode.string
            |> Just
      )
    , ( "background_color"
      , config.backgroundColor
            |> Maybe.map Color.Convert.colorToHex
            |> Maybe.map Encode.string
      )
    , ( "orientation"
      , config.orientation
            |> orientationToString
            |> Encode.string
            |> Just
      )
    , ( "display"
      , config.displayMode
            |> displayModeToAttribute
            |> Encode.string
            |> Just
      )
    , ( "categories"
      , config.categories
            |> List.map Category.toString
            |> Encode.list Encode.string
            |> Just
      )
    , ( "description"
      , config.description
            |> Encode.string
            |> Just
      )
    , ( "iarc_rating_id"
      , config.iarcRatingId
            |> Maybe.map Encode.string
      )
    , ( "name"
      , config.name
            |> Encode.string
            |> Just
      )
    , ( "prefer_related_applications"
      , Encode.bool False
            |> Just
        -- TODO remove hardcoding
      )
    , ( "related_applications"
      , Encode.list (\_ -> Encode.object []) []
            |> Just
        -- TODO remove hardcoding https://developer.mozilla.org/en-US/docs/Web/Manifest/related_applications
      )
    , ( "theme_color"
      , config.themeColor
            |> Maybe.map Color.Convert.colorToHex
            |> Maybe.map Encode.string
      )
    , ( "start_url"
      , config.startUrl
            |> PagePath.toString
            |> Encode.string
            |> Just
      )
    , ( "short_name"
      , config.shortName |> Maybe.map Encode.string
      )
    , ( "serviceworker"
      , Encode.object
            [ ( "src", Encode.string "/service-worker.js" )
            , ( "scope", Encode.string "/" )
            , ( "type", Encode.string "" )
            , ( "update_via_cache", Encode.string "none" )
            ]
            |> Just
      )
    ]
        |> List.filterMap
            (\( key, maybeValue ) ->
                case maybeValue of
                    Just value ->
                        Just ( key, value )

                    Nothing ->
                        Nothing
            )
        |> Encode.object
