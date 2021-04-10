module Data.Author exposing (Author, all, decoder, dillon, view)

import Cloudinary
import Element exposing (Element)
import Html.Attributes as Attr
import Json.Decode as Decode exposing (Decoder)
import List.Extra
import Pages.ImagePath as ImagePath exposing (ImagePath)


type alias Author =
    { name : String
    , avatar : ImagePath
    , bio : String
    }


all : List Author
all =
    [ dillon
    ]


dillon : Author
dillon =
    { name = "Dillon Kearns"
    , avatar = Cloudinary.url "v1602899672/elm-radio/dillon-profile_n2lqst.jpg" Nothing 140
    , bio = "Elm developer and educator. Founder of Incremental Elm Consulting."
    }


decoder : Decoder Author
decoder =
    Decode.string
        |> Decode.andThen
            (\lookupName ->
                case List.Extra.find (\currentAuthor -> currentAuthor.name == lookupName) all of
                    Just author ->
                        Decode.succeed author

                    Nothing ->
                        Decode.fail ("Couldn't find author with name " ++ lookupName ++ ". Options are " ++ String.join ", " (List.map .name all))
            )


view : List (Element.Attribute msg) -> Author -> Element msg
view attributes author =
    Element.image
        (Element.width (Element.px 70)
            :: Element.htmlAttribute (Attr.class "avatar")
            :: attributes
        )
        { src = ImagePath.toString author.avatar, description = author.name }
