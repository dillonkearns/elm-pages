module UnsplashImage exposing (UnsplashImage, decoder, default, fromId, imagePath, rawUrl)

import Json.Decode as Decode exposing (Decoder)
import Pages.Url
import Url.Builder exposing (string)


type UnsplashImage
    = UnsplashImage String


default : UnsplashImage
default =
    fromId "1587382668076-5101b7cd8eae"


imagePath : UnsplashImage -> Pages.Url.Url
imagePath (UnsplashImage url_) =
    url_
        |> Pages.Url.external


rawUrl : UnsplashImage -> String
rawUrl (UnsplashImage url_) =
    url_


fromId : String -> UnsplashImage
fromId id =
    UnsplashImage (url id)


decoder : Decoder UnsplashImage
decoder =
    Decode.string
        |> Decode.map fromId


url : String -> String
url photoId =
    Url.Builder.crossOrigin
        "https://images.unsplash.com"
        [ "photo-" ++ photoId ]
        [ string "auto" "format"
        , string "fit" "crop"
        , Url.Builder.int "w" 600
        , Url.Builder.int "q" 80
        ]
