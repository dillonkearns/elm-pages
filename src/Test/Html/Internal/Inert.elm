module Test.Html.Internal.Inert exposing (Node, fromElmHtml, fromHtml, parseAttribute, toElmHtml)

{-| Inert Html - that is, can't do anything with events.

@docs Node, fromElmHtml, fromHtml, parseAttribute, toElmHtml

-}

import Elm.Kernel.HtmlAsJson
import Html exposing (Html)
import Json.Decode
import Test.Html.Internal.ElmHtml.InternalTypes as InternalTypes exposing (ElmHtml(..), EventHandler, Facts, Tagger, decodeAttribute, decodeElmHtml)
import VirtualDom


type Node msg
    = Node (ElmHtml msg)


fromHtml : Html msg -> Result String (Node msg)
fromHtml html =
    case Json.Decode.decodeValue (decodeElmHtml taggedEventDecoder) (toJson html) of
        Ok elmHtml ->
            Ok (Node elmHtml)

        Err jsonError ->
            Err (Json.Decode.errorToString jsonError)


fromElmHtml : ElmHtml msg -> Node msg
fromElmHtml =
    Node


{-| Convert a Html node to a Json string
-}
toJson : Html a -> Json.Decode.Value
toJson node =
    Elm.Kernel.HtmlAsJson.toJson node


toElmHtml : Node msg -> ElmHtml msg
toElmHtml (Node elmHtml) =
    elmHtml


impossibleMessage : String
impossibleMessage =
    "An Inert Node fired an event handler. This should never happen! Please report this bug."


attributeToJson : Html.Attribute a -> Json.Decode.Value
attributeToJson attribute =
    Elm.Kernel.HtmlAsJson.attributeToJson attribute


parseAttribute : Html.Attribute a -> Result String InternalTypes.Attribute
parseAttribute attr =
    case Json.Decode.decodeValue decodeAttribute (attributeToJson attr) of
        Ok parsedAttribute ->
            Ok parsedAttribute

        Err jsonError ->
            Err
                ("Error internally processing Attribute for testing - please report this error message as a bug: "
                    ++ Json.Decode.errorToString jsonError
                )


{-| Gets the function out of a tagger
-}
taggerFunction : Tagger -> (a -> msg)
taggerFunction tagger =
    Elm.Kernel.HtmlAsJson.taggerFunction tagger


{-| Gets the decoder out of an EventHandler
-}
eventDecoder : EventHandler -> VirtualDom.Handler msg
eventDecoder eventHandler =
    Elm.Kernel.HtmlAsJson.eventHandler eventHandler


{-| Applies the taggers over the event handlers to have the complete event decoder
-}
taggedEventDecoder : List Tagger -> EventHandler -> VirtualDom.Handler msg
taggedEventDecoder taggers eventHandler =
    case taggers of
        [] ->
            eventDecoder eventHandler

        [ tagger ] ->
            mapHandler (taggerFunction tagger) (eventDecoder eventHandler)

        tagger :: rest ->
            mapHandler (taggerFunction tagger) (taggedEventDecoder rest eventHandler)


mapHandler : (a -> b) -> VirtualDom.Handler a -> VirtualDom.Handler b
mapHandler f handler =
    case handler of
        VirtualDom.Normal decoder ->
            VirtualDom.Normal (Json.Decode.map f decoder)

        VirtualDom.MayStopPropagation decoder ->
            VirtualDom.MayStopPropagation (Json.Decode.map (Tuple.mapFirst f) decoder)

        VirtualDom.MayPreventDefault decoder ->
            VirtualDom.MayPreventDefault (Json.Decode.map (Tuple.mapFirst f) decoder)

        VirtualDom.Custom decoder ->
            VirtualDom.Custom
                (Json.Decode.map
                    (\value ->
                        { message = f value.message
                        , stopPropagation = value.stopPropagation
                        , preventDefault = value.preventDefault
                        }
                    )
                    decoder
                )
