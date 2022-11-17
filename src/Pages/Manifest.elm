module Pages.Manifest exposing
    ( Config, Icon
    , init
    , withBackgroundColor, withCategories, withDisplayMode, withIarcRatingId, withLang, withOrientation, withShortName, withThemeColor
    , withField
    , DisplayMode(..), Orientation(..), IconPurpose(..)
    , generator
    , toJson
    )

{-| Represents the configuration of a
[web manifest file](https://developer.mozilla.org/en-US/docs/Web/Manifest).

You pass your `Pages.Manifest.Config` record into the `Pages.application` function
(from your generated `Pages.elm` file).

    import Pages.Manifest as Manifest
    import Pages.Manifest.Category

    manifest : Manifest.Config
    manifest =
        Manifest.init
            { name = static.siteName
            , description = "elm-pages - " ++ tagline
            , startUrl = Route.Index {} |> Route.toPath
            , icons =
                [ icon webp 192
                , icon webp 512
                , icon MimeType.Png 192
                , icon MimeType.Png 512
                ]
            }
            |> Manifest.withShortName "elm-pages"

@docs Config, Icon


## Builder options

@docs init

@docs withBackgroundColor, withCategories, withDisplayMode, withIarcRatingId, withLang, withOrientation, withShortName, withThemeColor


## Arbitrary Fields Escape Hatch

@docs withField


## Config options

@docs DisplayMode, Orientation, IconPurpose


## Generating a Manifest.json

@docs generator


## Functions for use by the generated code (`Pages.elm`)

@docs toJson

-}

import ApiRoute
import Color exposing (Color)
import Color.Convert
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Head
import Json.Encode as Encode
import LanguageTag exposing (LanguageTag, emptySubtags)
import LanguageTag.Country as Country
import LanguageTag.Language
import MimeType
import Pages.Manifest.Category as Category exposing (Category)
import Pages.Url
import Path exposing (Path)



{- TODO serviceworker https://developer.mozilla.org/en-US/docs/Web/Manifest/serviceworker
   This is mandatory... need to process this in a special way
-}
-- TODO use language https://developer.mozilla.org/en-US/docs/Web/Manifest/lang


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


{-| Setup a minimal Manifest.Config. You can then use the `with...` builder functions to set additional options.
-}
init :
    { description : String
    , name : String
    , startUrl : Path
    , icons : List Icon
    }
    -> Config
init options =
    { backgroundColor = Nothing
    , categories = []
    , displayMode = Standalone
    , orientation = Portrait
    , description = options.description
    , iarcRatingId = Nothing
    , name = options.name
    , themeColor = Nothing
    , startUrl = options.startUrl
    , shortName = Nothing
    , icons = options.icons
    , lang = usEnglish
    , otherFields = Dict.empty
    }


usEnglish : LanguageTag
usEnglish =
    LanguageTag.Language.en
        |> LanguageTag.build
            { emptySubtags
                | region = Just Country.us
            }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/background_color>.
-}
withBackgroundColor : Color -> Config -> Config
withBackgroundColor color config =
    { config | backgroundColor = Just color }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/categories>.
-}
withCategories : List Category -> Config -> Config
withCategories categories config =
    { config | categories = categories ++ config.categories }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/display>.
-}
withDisplayMode : DisplayMode -> Config -> Config
withDisplayMode displayMode config =
    { config | displayMode = displayMode }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/orientation>.
-}
withOrientation : Orientation -> Config -> Config
withOrientation orientation config =
    { config | orientation = orientation }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/iarc_rating_id>.
-}
withIarcRatingId : String -> Config -> Config
withIarcRatingId iarcRatingId config =
    { config | iarcRatingId = Just iarcRatingId }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/theme_color>.
-}
withThemeColor : Color -> Config -> Config
withThemeColor themeColor config =
    { config | themeColor = Just themeColor }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/short_name>.
-}
withShortName : String -> Config -> Config
withShortName shortName config =
    { config | shortName = Just shortName }


{-| Set <https://developer.mozilla.org/en-US/docs/Web/Manifest/lang>.
-}
withLang : LanguageTag -> Config -> Config
withLang languageTag config =
    { config | lang = languageTag }


{-| Escape hatch for specifying fields that aren't exposed through this module otherwise. The possible supported properties
in a manifest file can change over time, so see [MDN manifest.json docs](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json)
for a full listing of the current supported properties.
-}
withField : String -> Encode.Value -> Config -> Config
withField name value config =
    { config
        | otherFields = config.otherFields |> Dict.insert name value
    }


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
-}
type alias Config =
    { backgroundColor : Maybe Color
    , categories : List Category
    , displayMode : DisplayMode
    , orientation : Orientation
    , description : String
    , iarcRatingId : Maybe String
    , name : String
    , themeColor : Maybe Color

    -- https://developer.mozilla.org/en-US/docs/Web/Manifest/start_url
    , startUrl : Path

    -- https://developer.mozilla.org/en-US/docs/Web/Manifest/short_name
    , shortName : Maybe String
    , icons : List Icon
    , lang : LanguageTag
    , otherFields : Dict String Encode.Value
    }


{-| <https://developer.mozilla.org/en-US/docs/Web/Manifest/icons>
-}
type alias Icon =
    { src : Pages.Url.Url
    , sizes : List ( Int, Int )
    , mimeType : Maybe MimeType.MimeImage
    , purposes : List IconPurpose
    }


{-| <https://w3c.github.io/manifest/#dfn-icon-purposes>
-}
type IconPurpose
    = IconPurposeMonochrome
    | IconPurposeMaskable
    | IconPurposeAny


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


encodeIcon : String -> Icon -> Encode.Value
encodeIcon canonicalSiteUrl icon =
    encodeMaybeObject
        [ ( "src", icon.src |> Pages.Url.toAbsoluteUrl canonicalSiteUrl |> Encode.string |> Just )
        , ( "type", icon.mimeType |> Maybe.map MimeType.Image |> Maybe.map MimeType.toString |> Maybe.map Encode.string )
        , ( "sizes", icon.sizes |> nonEmptyList |> Maybe.map sizesString |> Maybe.map Encode.string )
        , ( "purpose", icon.purposes |> nonEmptyList |> Maybe.map purposesString |> Maybe.map Encode.string )
        ]


purposesString : List IconPurpose -> String
purposesString purposes =
    purposes
        |> List.map purposeToString
        |> String.join " "


purposeToString : IconPurpose -> String
purposeToString purpose =
    case purpose of
        IconPurposeMonochrome ->
            "monochrome"

        IconPurposeMaskable ->
            "maskable"

        IconPurposeAny ->
            "any"


sizesString : List ( Int, Int ) -> String
sizesString sizes =
    sizes
        |> List.map (\( x, y ) -> String.fromInt x ++ "x" ++ String.fromInt y)
        |> String.join " "


nonEmptyList : List a -> Maybe (List a)
nonEmptyList list =
    if List.isEmpty list then
        Nothing

    else
        Just list


{-| A generator for Api.elm to include a manifest.json.
-}
generator : String -> DataSource Config -> ApiRoute.ApiRoute ApiRoute.Response
generator canonicalSiteUrl config =
    ApiRoute.succeed
        (config
            |> DataSource.map (toJson canonicalSiteUrl >> Encode.encode 0)
        )
        |> ApiRoute.literal "manifest.json"
        |> ApiRoute.single
        |> ApiRoute.withGlobalHeadTags
            (DataSource.succeed
                [ Head.manifestLink "/manifest.json"
                ]
            )


{-| Feel free to use this, but in 99% of cases you won't need it. The generated
code will run this for you to generate your `manifest.json` file automatically!
-}
toJson : String -> Config -> Encode.Value
toJson canonicalSiteUrl config =
    [ ( "dir", Encode.string "auto" |> Just )
    , ( "lang"
      , config.lang
            |> LanguageTag.toString
            |> Encode.string
            |> Just
      )
    , ( "icons"
      , config.icons
            |> Encode.list (encodeIcon canonicalSiteUrl)
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
      , Path.toAbsolute config.startUrl
            |> Encode.string
            |> Just
      )
    , ( "short_name"
      , config.shortName |> Maybe.map Encode.string
      )
    , ( "scope"
      , Encode.string "/" |> Just
      )
    ]
        ++ (config.otherFields
                |> Dict.toList
                |> List.map (Tuple.mapSecond Just)
           )
        |> encodeMaybeObject


encodeMaybeObject : List ( String, Maybe Encode.Value ) -> Encode.Value
encodeMaybeObject list =
    list
        |> List.filterMap
            (\( key, maybeValue ) ->
                case maybeValue of
                    Just value ->
                        Just ( key, value )

                    Nothing ->
                        Nothing
            )
        |> Encode.object
