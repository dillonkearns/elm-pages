module Session exposing (..)

import Codec exposing (Codec)
import Dict exposing (Dict)
import Json.Decode
import Json.Encode
import OptimizedDecoder


type Session decoded
    = Session decoded


type alias Decoder decoded =
    OptimizedDecoder.Decoder decoded


type SessionUpdate
    = SessionUpdate (Dict String Json.Encode.Value)


noUpdates : SessionUpdate
noUpdates =
    SessionUpdate Dict.empty


oneUpdate : String -> Json.Encode.Value -> SessionUpdate
oneUpdate string value =
    SessionUpdate (Dict.singleton string value)


type NotLoadedReason
    = NoCookies
    | MissingHeaders


succeed : constructor -> Decoder constructor
succeed constructor =
    constructor
        |> OptimizedDecoder.succeed


decoder =
    -- TODO have a way to commit updates using this as the starting point
    OptimizedDecoder.dict OptimizedDecoder.value


setValues : SessionUpdate -> Dict String Json.Decode.Value -> Json.Encode.Value
setValues (SessionUpdate dict) original =
    Dict.union dict original
        |> Dict.toList
        |> Json.Encode.object



--|> Decoder


get : ( String, Codec a ) -> Result String a
get ( string, codec ) =
    Err "TODO"
