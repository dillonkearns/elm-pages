module MySession exposing (..)

import Codec
import Dict
import Secrets
import Session


withSession =
    Session.withSession
        { name = "mysession"
        , secrets =
            Secrets.succeed
                (\secret -> [ secret ])
                |> Secrets.with "SESSION_SECRET"
        , sameSite = "lax"
        }


schema =
    { name = ( "name", Codec.string )
    , message = ( "message", Codec.string )
    , user =
        ( "user"
        , Codec.object User
            |> Codec.field "id" .id Codec.int
            |> Codec.buildObject
        )
    }


type alias User =
    { id : Int
    }


schemaUpdate getter value =
    let
        ( name, codec ) =
            schema |> getter
    in
    Session.oneUpdate name ((codec |> Codec.encodeToString 1) value)


schemaGet getter sessionDict =
    let
        ( name, codec ) =
            schema |> getter
    in
    sessionDict
        |> Dict.get name
        |> Maybe.map (codec |> Codec.decodeString)


exampleSchemaUpdate =
    schemaUpdate .name "John Doe"


exampleSchemaGet =
    schemaGet .name


exampleUpdate =
    Session.oneUpdate "name" "NAME"



--|> Session.withFlash "message" ("Welcome " ++ name ++ "!")
