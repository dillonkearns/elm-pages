module Pages.Manifest exposing (Config, DisplayMode(..), Orientation(..), toJson)

import Color exposing (Color)
import Color.Convert
import Json.Encode as Encode
import Pages.Manifest.Category as Category exposing (Category)
import Pages.Path as Path exposing (Path)



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
    , startUrl : Path pathKey Path.ToPage

    -- https://developer.mozilla.org/en-US/docs/Web/Manifest/short_name
    , shortName : Maybe String
    , sourceIcon : Path pathKey Path.ToImage
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


toJson : Config pathKey -> Encode.Value
toJson config =
    [ ( "sourceIcon"
      , config.sourceIcon
            |> Path.toString
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
            |> Path.toString
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
