module Json.Decode.Exploration exposing
    ( decodeString, decodeValue, strict, DecodeResult(..), Value
    , Errors, Error(..), errorsToString, Warnings, Warning(..), warningsToString
    , ExpectedType(..)
    , Decoder, string, bool, int, float
    , nullable, list, array, dict, keyValuePairs
    , isObject, isArray
    , field, at, index
    , maybe, oneOf
    , lazy, value, null, check, succeed, fail, warn, andThen
    , map, map2, map3, map4, map5, map6, map7, map8, andMap
    , stripString, stripValue
    )

{-| This package presents a somewhat experimental approach to JSON decoding. Its
API looks very much like the core `Json.Decode` API. The major differences are
the final `decodeString` and `decodeValue` functions, which return a
`DecodeResult a`.

Decoding with this library can result in one of 4 possible outcomes:

  - The input wasn't valid JSON
  - One or more errors occured
  - Decoding succeeded but produced warnings
  - Decoding succeeded without warnings

Both the `Errors` and `Warnings` types are (mostly) machine readable: they are
implemented as a recursive datastructure that points to the location of the
error in the input json, producing information about what went wrong (i.e. "what
was the expected type, and what did the actual value look like").

Further, this library also adds a few extra `Decoder`s that help with making
assertions about the structure of the JSON while decoding.

For convenience, this library also includes a `Json.Decode.Exploration.Pipeline`
module which is largely a copy of [`NoRedInk/elm-decode-pipeline`][edp].

[edp]: http://package.elm-lang.org/packages/NoRedInk/elm-decode-pipeline/latest


# Running a `Decoder`

Runing a `Decoder` works largely the same way as it does in the familiar core
library. There is one serious caveat, however:

> This library does **not** allowing decoding non-serializable JS values.

This means that trying to use this library to decode a `Value` which contains
non-serializable information like `function`s will not work. It will, however,
result in a `BadJson` result.

Trying to use this library on cyclic values (like HTML events) is quite likely
to blow up completely. Don't try this, except maybe at home.

@docs decodeString, decodeValue, strict, DecodeResult, Value


## Dealing with warnings and errors

@docs Errors, Error, errorsToString, Warnings, Warning, warningsToString
@docs ExpectedType


# Primitives

@docs Decoder, string, bool, int, float


# Data Structures

@docs nullable, list, array, dict, keyValuePairs


# Structural ascertainments

@docs isObject, isArray


# Object Primitives

@docs field, at, index


# Inconsistent Structure

@docs maybe, oneOf


# Fancy Decoding

@docs lazy, value, null, check, succeed, fail, warn, andThen


# Mapping

**Note:** If you run out of map functions, take a look at [the pipeline module][pipe]
which makes it easier to handle large objects.

[pipe]: http://package.elm-lang.org/packages/zwilias/json-decode-exploration/latest/Json-Decode-Exploration-Pipeline

@docs map, map2, map3, map4, map5, map6, map7, map8, andMap


# Stripping

@docs stripString, stripValue

-}

import Array exposing (Array)
import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Decode.Exploration.Located as Located exposing (Located(..))
import Json.Encode as Encode
import List.Nonempty as Nonempty exposing (Nonempty(..))


{-| A simple type alias for `Json.Decode.Value`.
-}
type alias Value =
    Decode.Value


{-| Decoding may fail with 1 or more errors, so `Errors` is a
[`Nonempty`][nonempty] of errors.

[nonempty]: http://package.elm-lang.org/packages/mgold/elm-nonempty-list/latest/List-Nonempty

-}
type alias Errors =
    Nonempty (Located Error)


{-| The most basic kind of an `Error` is `Failure`, which comes annotated with
a string describing the failure, and the JSON `Value` that was encountered
instead.

The other cases describe the "path" to where the error occurred.

-}
type Error
    = BadOneOf (List Errors)
    | Expected ExpectedType Value
    | Failure String (Maybe Value)


{-| An enumeration of the different types that could be expected by a decoder.
-}
type ExpectedType
    = TString
    | TBool
    | TInt
    | TNumber
    | TArray
    | TObject
    | TArrayIndex Int
    | TObjectField String
    | TNull


{-| Decoding may generate warnings. In case the result is a `WithWarnings`, you
will have 1 or more warnings, as a `Nonempty` list.
-}
type alias Warnings =
    Nonempty (Located Warning)


{-| Like with errors, the most basic warning is an unused value. The other cases
describe the path to the warnings.
-}
type Warning
    = UnusedValue Value
    | UnusedField String
    | UnusedIndex Int
    | Warning String Value


{-| Decoding can have 4 different outcomes:

  - `BadJson` occurs when the JSON string isn't valid JSON, or the `Value`
    contains non-JSON primitives like functions.
  - `Errors` means errors occurred while running your decoder and contains the
    [`Errors`](#Errors) that occurred.
  - `WithWarnings` means decoding succeeded but produced one or more
    [`Warnings`](#Warnings).
  - `Success` is the best possible outcome: All went well!

-}
type DecodeResult a
    = BadJson
    | Errors Errors
    | WithWarnings Warnings a
    | Success a


{-| Kind of the core idea of this library. Think of it as a piece of data that
describes _how_ to read and transform JSON. You can use `decodeString` and
`decodeValue` to actually execute a decoder on JSON.
-}
type Decoder a
    = Decoder (AnnotatedValue -> ( AnnotatedValue, Result Errors (Acc a) ))


type alias Acc a =
    { value : a
    , warnings : List (Located Warning)
    }


mapAcc : (a -> b) -> Acc a -> Acc b
mapAcc f acc =
    { warnings = acc.warnings
    , value = f acc.value
    }


ok : AnnotatedValue -> a -> ( AnnotatedValue, Result e (Acc a) )
ok json val =
    ( json
    , Ok
        { value = val
        , warnings = []
        }
    )


{-| Run a `Decoder` on a `Value`.

Note that this may still fail with a `BadJson` if there are non-JSON compatible
values in the provided `Value`. In particular, don't attempt to use this library
when decoding `Event`s - it will blow up. Badly.

-}
decodeValue : Decoder a -> Value -> DecodeResult a
decodeValue (Decoder decoderFn) val =
    case decode val of
        Err _ ->
            BadJson

        Ok json ->
            case decoderFn json of
                ( _, Err errors ) ->
                    Errors errors

                ( annVal, Ok acc ) ->
                    case acc.warnings ++ gatherWarnings annVal of
                        [] ->
                            Success acc.value

                        x :: xs ->
                            WithWarnings (Nonempty x xs) acc.value


{-| Decode a JSON string. If the string isn't valid JSON, this will fail with a
`BadJson` result.
-}
decodeString : Decoder a -> String -> DecodeResult a
decodeString decoder jsonString =
    case Decode.decodeString Decode.value jsonString of
        Err _ ->
            BadJson

        Ok json ->
            decodeValue decoder json


{-| Reduce JSON down to what is needed to ensure decoding succeeds.
-}
stripValue : Decoder a -> Value -> Result Errors Value
stripValue (Decoder decoderFn) val =
    case decode val of
        Err _ ->
            Err (Nonempty (Here (Failure "Bad json" Nothing)) [])

        Ok json ->
            case decoderFn json of
                ( annVal, Ok _ ) ->
                    Ok (stripAnnotatedValue annVal)

                ( _, Err e ) ->
                    Err e


{-| Reduce JSON down to what is needed to ensure decoding succeeds.
-}
stripString : Decoder a -> String -> Result Errors String
stripString decoder jsonString =
    case Decode.decodeString Decode.value jsonString of
        Err _ ->
            Err (Nonempty (Here (Failure "Bad json" Nothing)) [])

        Ok v ->
            stripValue decoder v
                |> Result.map (Encode.encode 0)


{-| A decoder that will ignore the actual JSON and succeed with the provided
value. Note that this may still fail when dealing with an invalid JSON string.

If a value in the JSON ends up being ignored because of this, this will cause a
warning.

    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ null """
        |> decodeString (value |> andThen (\_ -> succeed "hello world"))
    --> Success "hello world"


    """ null """
        |> decodeString (succeed "hello world")
    --> WithWarnings
    -->     (Nonempty (Here <| UnusedValue Encode.null) [])
    -->     "hello world"


    """ foo """
        |> decodeString (succeed "hello world")
    --> BadJson

-}
succeed : a -> Decoder a
succeed val =
    Decoder <| \json -> ok json val


{-| Ignore the json and fail with a provided message.

    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode

    """ "hello" """
        |> decodeString (fail "failure")
    --> Errors (Nonempty (Here <| Failure "failure" (Just <| Encode.string "hello")) [])

-}
fail : String -> Decoder a
fail message =
    Decoder <|
        \json ->
            encode json
                |> Just
                |> Failure message
                |> Here
                |> Nonempty.fromElement
                |> Err
                |> Tuple.pair json


{-| Add a warning to the result of a decoder.

For example, imagine we are upgrading some internal JSON format. We might add a
temporary workaround for backwards compatibility. By adding a warning to the
decoder, we can flag these or print them during development.

    import List.Nonempty as Nonempty
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode

    decoder : Decoder (List Int)
    decoder =
        oneOf
            [ list int
            , int |> map List.singleton |> warn "Converted to list"
            ]

    expectedWarnings : Warnings
    expectedWarnings =
        Warning "Converted to list" (Encode.int 123)
            |> Here
            |> Nonempty.fromElement

    """ 123 """
       |>  decodeString decoder
    --> WithWarnings expectedWarnings [ 123 ]

Note that warnings added to a failing decoder won't show up.

    """ null """
        |> decodeString (warn "this might be null" int)
    --> Errors (Nonempty.fromElement (Here <| Expected TInt Encode.null))

-}
warn : String -> Decoder a -> Decoder a
warn message (Decoder decoderFn) =
    Decoder <|
        \json ->
            case decoderFn json of
                ( annVal, Err e ) ->
                    ( annVal, Err e )

                ( annVal, Ok acc ) ->
                    let
                        warning : Located Warning
                        warning =
                            Here <| Warning message (encode annVal)
                    in
                    ( annVal, Ok { acc | warnings = warning :: acc.warnings } )


{-| Decode a string.

    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ "hello world" """
        |> decodeString string
    --> Success "hello world"


    """ 123 """
        |> decodeString string
    --> Errors (Nonempty (Here <| Expected TString (Encode.int 123)) [])

-}
string : Decoder String
string =
    Decoder <|
        \json ->
            case json of
                String _ val ->
                    ok (markUsed json) val

                _ ->
                    expected TString json


{-| Extract a piece without actually decoding it.

If a structure is decoded as a `value`, everything _in_ the structure will be
considered as having been used and will not appear in `UnusedValue` warnings.

    import Json.Encode as Encode


    """ [ 123, "world" ] """
        |> decodeString value
    --> Success (Encode.list identity [ Encode.int 123, Encode.string "world" ])

-}
value : Decoder Value
value =
    Decoder <|
        \json ->
            ok (markUsed json) (encode json)


{-| Decode a number into a `Float`.

    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ 12.34 """
        |> decodeString float
    --> Success 12.34


    """ 12 """
        |> decodeString float
    --> Success 12


    """ null """
        |> decodeString float
    --> Errors (Nonempty (Here <| Expected TNumber Encode.null) [])

-}
float : Decoder Float
float =
    Decoder <|
        \json ->
            case json of
                Number _ val ->
                    ok (markUsed json) val

                _ ->
                    expected TNumber json


{-| Decode a number into an `Int`.

    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ 123 """
        |> decodeString int
    --> Success 123


    """ 0.1 """
        |> decodeString int
    --> Errors <|
    -->   Nonempty
    -->     (Here <| Expected TInt (Encode.float 0.1))
    -->     []

-}
int : Decoder Int
int =
    Decoder <|
        \json ->
            case json of
                Number _ val ->
                    if toFloat (round val) == val then
                        ok (markUsed json) (round val)

                    else
                        expected TInt json

                _ ->
                    expected TInt json


{-| Decode a boolean value.

    """ [ true, false ] """
        |> decodeString (list bool)
    --> Success [ True, False ]

-}
bool : Decoder Bool
bool =
    Decoder <|
        \json ->
            case json of
                Bool _ val ->
                    ok (markUsed json) val

                _ ->
                    expected TBool json


{-| Decode a `null` and succeed with some value.

    """ null """
        |> decodeString (null "it was null")
    --> Success "it was null"

Note that `undefined` and `null` are not the same thing. This cannot be used to
verify that a field is _missing_, only that it is explicitly set to `null`.

    """ { "foo": null } """
        |> decodeString (field "foo" (null ()))
    --> Success ()


    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ { } """
        |> decodeString (field "foo" (null ()))
    --> Errors <|
    -->   Nonempty
    -->     (Here <| Expected (TObjectField "foo") (Encode.object []))
    -->     []

-}
null : a -> Decoder a
null val =
    Decoder <|
        \json ->
            case json of
                Null _ ->
                    ok (Null True) val

                _ ->
                    expected TNull json


{-| Decode a list of values, decoding each entry with the provided decoder.

    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ [ "foo", "bar" ] """
        |> decodeString (list string)
    --> Success [ "foo", "bar" ]


    """ [ "foo", null ] """
        |> decodeString (list string)
    --> Errors <|
    -->   Nonempty
    -->     (AtIndex 1 <|
    -->       Nonempty (Here <| Expected TString Encode.null) []
    -->     )
    -->     []

-}
list : Decoder a -> Decoder (List a)
list (Decoder decoderFn) =
    let
        accumulate :
            ( Bool, AnnotatedValue )
            -> ( Int, List ( Bool, AnnotatedValue ), Result Errors ( List (Located Warning), List a ) )
            -> ( Int, List ( Bool, AnnotatedValue ), Result Errors ( List (Located Warning), List a ) )
        accumulate ( used, val ) ( idx, jsonAcc, acc ) =
            case ( acc, decoderFn val ) of
                ( Err errors, ( annVal, Err newErrors ) ) ->
                    ( idx - 1
                    , ( True, annVal ) :: jsonAcc
                    , Err <| Nonempty.cons (AtIndex idx newErrors) errors
                    )

                ( Err errors, ( annVal, _ ) ) ->
                    ( idx - 1, ( True, annVal ) :: jsonAcc, Err errors )

                ( _, ( annVal, Err errors ) ) ->
                    ( idx - 1
                    , ( True, annVal ) :: jsonAcc
                    , Err <| Nonempty.fromElement (AtIndex idx errors)
                    )

                ( Ok ( warnAcc, valAcc ), ( annVal, Ok res ) ) ->
                    ( idx - 1
                    , ( True, annVal ) :: jsonAcc
                    , Ok ( res.warnings ++ warnAcc, res.value :: valAcc )
                    )

        finalize : ( List (Located Warning), b ) -> Acc b
        finalize ( warnings, values ) =
            { warnings = warnings, value = values }
    in
    Decoder <|
        \json ->
            case json of
                Array _ values ->
                    List.foldr accumulate
                        ( List.length values - 1, [], Ok ( [], [] ) )
                        values
                        |> (\( _, jsonEntries, res ) ->
                                ( Array True jsonEntries
                                , Result.map finalize res
                                )
                           )

                _ ->
                    expected TArray json


{-| _Convenience function._ Decode a JSON array into an Elm `Array`.

    import Array

    """ [ 1, 2, 3 ] """
        |> decodeString (array int)
    --> Success <| Array.fromList [ 1, 2, 3 ]

-}
array : Decoder a -> Decoder (Array a)
array decoder =
    map Array.fromList (list decoder)


{-| _Convenience function._ Decode a JSON object into an Elm `Dict String`.

    import Dict


    """ { "foo": "bar", "bar": "hi there" } """
        |> decodeString (dict string)
    --> Success <| Dict.fromList
    -->   [ ( "bar", "hi there" )
    -->   , ( "foo", "bar" )
    -->   ]

-}
dict : Decoder v -> Decoder (Dict String v)
dict decoder =
    map Dict.fromList (keyValuePairs decoder)


{-| A Decoder to ascertain that a JSON value _is_ in fact, a JSON object.

Using this decoder marks the object itself as used, without touching any of its
children. It is, as such, fairly well behaved.

    import List.Nonempty as Nonempty
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ { } """
        |> decodeString isObject
    --> Success ()


    """ [] """
        |> decodeString isObject
    --> Errors <| Nonempty.fromElement <| Here <| Expected TObject (Encode.list identity [])

-}
isObject : Decoder ()
isObject =
    Decoder <|
        \json ->
            case json of
                Object _ pairs ->
                    ok (Object True pairs) ()

                _ ->
                    expected TObject json


{-| Similar to `isObject`, a decoder to ascertain that a JSON value is a JSON
array.

    import List.Nonempty as Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ [] """
        |> decodeString isArray
    --> Success ()


    """ [ "foo" ] """
        |> decodeString isArray
    --> WithWarnings (Nonempty (Here (UnusedIndex 0)) []) ()


    """ null """
        |> decodeString isArray
    --> Errors <| Nonempty.fromElement <| Here <| Expected TArray Encode.null

-}
isArray : Decoder ()
isArray =
    Decoder <|
        \json ->
            case json of
                Array _ values ->
                    ok (Array True values) ()

                _ ->
                    expected TArray json


{-| Decode a specific index using a specified `Decoder`.

    import List.Nonempty exposing (Nonempty(..))
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ [ "hello", 123 ] """
        |> decodeString (map2 Tuple.pair (index 0 string) (index 1 int))
    --> Success ( "hello", 123 )


    """ [ "hello", "there" ] """
        |> decodeString (index 1 string)
    --> WithWarnings (Nonempty (AtIndex 0 (Nonempty (Here (UnusedValue (Encode.string "hello"))) [])) [])
    -->   "there"

-}
index : Int -> Decoder a -> Decoder a
index idx (Decoder decoderFn) =
    let
        finalize :
            ( List ( Bool, AnnotatedValue ), List (Located Warning), Maybe (Result Errors a) )
            -> ( AnnotatedValue, Result Errors (Acc a) )
        finalize ( values, warnings, res ) =
            case res of
                Nothing ->
                    expected (TArrayIndex idx) (Array True values)

                Just (Err e) ->
                    ( Array True values, Err e )

                Just (Ok v) ->
                    ( Array True values, Ok { warnings = warnings, value = v } )

        accumulate :
            ( Bool, AnnotatedValue )
            -> ( Int, ( List ( Bool, AnnotatedValue ), List (Located Warning), Maybe (Result Errors a) ) )
            -> ( Int, ( List ( Bool, AnnotatedValue ), List (Located Warning), Maybe (Result Errors a) ) )
        accumulate ( used, val ) ( i, ( acc, warnings, result ) ) =
            if i == idx then
                case decoderFn val of
                    ( annVal, Err e ) ->
                        ( i - 1
                        , ( ( True, annVal ) :: acc
                          , warnings
                          , Just <| Err <| Nonempty.fromElement <| AtIndex i e
                          )
                        )

                    ( annVal, Ok res ) ->
                        ( i - 1
                        , ( ( True, annVal ) :: acc
                          , res.warnings ++ warnings
                          , Just <| Ok res.value
                          )
                        )

            else
                ( i - 1
                , ( ( used || result /= Nothing, val ) :: acc
                  , warnings
                  , result
                  )
                )
    in
    Decoder <|
        \json ->
            case json of
                Array _ values ->
                    List.foldr
                        accumulate
                        ( List.length values - 1, ( [], [], Nothing ) )
                        values
                        |> Tuple.second
                        |> finalize

                _ ->
                    expected TArray json


{-| Decode a JSON object into a list of key-value pairs. The decoder you provide
will be used to decode the values.

    """ { "foo": "bar", "hello": "world" } """
        |> decodeString (keyValuePairs string)
    --> Success [ ( "foo", "bar" ), ( "hello", "world" ) ]

-}
keyValuePairs : Decoder a -> Decoder (List ( String, a ))
keyValuePairs (Decoder decoderFn) =
    let
        accumulate :
            ( Bool, String, AnnotatedValue )
            -> ( List ( Bool, String, AnnotatedValue ), Result Errors ( List (Located Warning), List ( String, a ) ) )
            -> ( List ( Bool, String, AnnotatedValue ), Result Errors ( List (Located Warning), List ( String, a ) ) )
        accumulate ( used, key, val ) ( jsonAcc, acc ) =
            case ( acc, decoderFn val ) of
                ( Err e, ( annVal, Err new ) ) ->
                    ( ( True, key, annVal ) :: jsonAcc
                    , Err <| Nonempty.cons (InField key new) e
                    )

                ( Err e, ( annVal, _ ) ) ->
                    ( ( True, key, annVal ) :: jsonAcc
                    , Err e
                    )

                ( _, ( annVal, Err e ) ) ->
                    ( ( True, key, annVal ) :: jsonAcc, Err <| Nonempty.fromElement (InField key e) )

                ( Ok ( warningsAcc, accAcc ), ( annVal, Ok res ) ) ->
                    ( ( True, key, annVal ) :: jsonAcc
                    , Ok
                        ( List.map (Nonempty.fromElement >> InField key) res.warnings ++ warningsAcc
                        , ( key, res.value ) :: accAcc
                        )
                    )

        finalize : ( List (Located Warning), b ) -> Acc b
        finalize ( warnings, val ) =
            { warnings = warnings
            , value = val
            }
    in
    Decoder <|
        \json ->
            case json of
                Object _ kvPairs ->
                    List.foldr accumulate ( [], Ok ( [], [] ) ) kvPairs
                        |> (\( entries, res ) -> ( Object True entries, Result.map finalize res ))

                _ ->
                    expected TObject json


{-| Decode the content of a field using a provided decoder.

    import List.Nonempty as Nonempty
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode

    """ { "foo": "bar" } """
        |> decodeString (field "foo" string)
    --> Success "bar"


    """ [ { "foo": "bar" }, { "foo": "baz", "hello": "world" } ] """
        |> decodeString (list (field "foo" string))
    --> WithWarnings expectedWarnings [ "bar", "baz" ]


    expectedWarnings : Warnings
    expectedWarnings =
        UnusedField "hello"
            |> Here
            |> Nonempty.fromElement
            |> AtIndex 1
            |> Nonempty.fromElement

-}
field : String -> Decoder a -> Decoder a
field fieldName (Decoder decoderFn) =
    let
        accumulate :
            ( Bool, String, AnnotatedValue )
            -> ( List ( Bool, String, AnnotatedValue ), List (Located Warning), Maybe (Result Errors a) )
            -> ( List ( Bool, String, AnnotatedValue ), List (Located Warning), Maybe (Result Errors a) )
        accumulate ( used, key, val ) ( acc, warnings, result ) =
            if key == fieldName then
                case decoderFn val of
                    ( annVal, Err e ) ->
                        ( ( True, key, annVal ) :: acc
                        , warnings
                        , Just <| Err <| Nonempty.fromElement <| InField key e
                        )

                    ( annVal, Ok res ) ->
                        ( ( True, key, annVal ) :: acc
                        , List.map (Nonempty.fromElement >> InField key) res.warnings ++ warnings
                        , Just <| Ok res.value
                        )

            else
                ( ( used, key, val ) :: acc, warnings, result )

        finalize :
            ( List ( Bool, String, AnnotatedValue ), List (Located Warning), Maybe (Result Errors a) )
            -> ( AnnotatedValue, Result Errors (Acc a) )
        finalize ( values, warnings, res ) =
            case res of
                Nothing ->
                    expected (TObjectField fieldName) (Object True values)

                Just (Err e) ->
                    ( Object True values, Err e )

                Just (Ok v) ->
                    ( Object True values, Ok { warnings = warnings, value = v } )
    in
    Decoder <|
        \json ->
            case json of
                Object _ kvPairs ->
                    List.foldr accumulate ( [], [], Nothing ) kvPairs
                        |> finalize

                _ ->
                    expected TObject json


{-| Decodes a value at a certain path, using a provided decoder. Essentially,
writing `at [ "a", "b", "c" ]  string` is sugar over writing
`field "a" (field "b" (field "c" string))`}.

    """ { "a": { "b": { "c": "hi there" } } } """
        |> decodeString (at [ "a", "b", "c" ] string)
    --> Success "hi there"

-}
at : List String -> Decoder a -> Decoder a
at fields decoder =
    List.foldr field decoder fields



-- Choosing


{-| Tries a bunch of decoders. The first one to not fail will be the one used.

If all fail, the errors are collected into a `BadOneOf`.

    import List.Nonempty as Nonempty
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode

    """ [ 12, "whatever" ] """
        |> decodeString (list <| oneOf [ map String.fromInt int, string ])
    --> Success [ "12", "whatever" ]


    """ null """
        |> decodeString (oneOf [ string, map String.fromInt int ])
    --> Errors <| Nonempty.fromElement <| Here <| BadOneOf
    -->   [ Nonempty.fromElement <| Here <| Expected TString Encode.null
    -->   , Nonempty.fromElement <| Here <| Expected TInt Encode.null
    -->   ]

-}
oneOf : List (Decoder a) -> Decoder a
oneOf decoders =
    Decoder <|
        \json ->
            oneOfHelp decoders json []


oneOfHelp :
    List (Decoder a)
    -> AnnotatedValue
    -> List Errors
    -> ( AnnotatedValue, Result Errors (Acc a) )
oneOfHelp decoders val errorAcc =
    case decoders of
        [] ->
            BadOneOf (List.reverse errorAcc)
                |> Here
                |> Nonempty.fromElement
                |> Err
                |> Tuple.pair val

        (Decoder decoderFn) :: rest ->
            case decoderFn val of
                ( annVal, Ok res ) ->
                    ( annVal, Ok res )

                ( annVal, Err e ) ->
                    oneOfHelp rest annVal (e :: errorAcc)


{-| Decodes successfully and wraps with a `Just`, handling failure by succeeding
with `Nothing`.

    import List.Nonempty as Nonempty
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ [ "foo", 12 ] """
        |> decodeString (list <| maybe string)
    --> WithWarnings expectedWarnings [ Just "foo", Nothing ]


    expectedWarnings : Warnings
    expectedWarnings =
        UnusedValue (Encode.int 12)
            |> Here
            |> Nonempty.fromElement
            |> AtIndex 1
            |> Nonempty.fromElement

-}
maybe : Decoder a -> Decoder (Maybe a)
maybe decoder =
    oneOf [ map Just decoder, succeed Nothing ]


{-| Decodes successfully and wraps with a `Just`. If the values is `null`
succeeds with `Nothing`.

    """ [ { "foo": "bar" }, { "foo": null } ] """
        |> decodeString (list <| field "foo" <| nullable string)
    --> Success [ Just "bar", Nothing ]

-}
nullable : Decoder a -> Decoder (Maybe a)
nullable decoder =
    oneOf [ null Nothing, map Just decoder ]



--


{-| Required when using (mutually) recursive decoders.
-}
lazy : (() -> Decoder a) -> Decoder a
lazy toDecoder =
    Decoder <|
        \json ->
            let
                (Decoder decoderFn) =
                    toDecoder ()
            in
            decoderFn json



-- Extras


{-| Useful for checking a value in the JSON matches the value you expect it to
have. If it does, succeeds with the second decoder. If it doesn't it fails.

This can be used to decode union types:

    type Pet = Cat | Dog | Rabbit

    petDecoder : Decoder Pet
    petDecoder =
        oneOf
            [ check string "cat" <| succeed Cat
            , check string "dog" <| succeed Dog
            , check string "rabbit" <| succeed Rabbit
            ]

    """ [ "dog", "rabbit", "cat" ] """
        |> decodeString (list petDecoder)
    --> Success [ Dog, Rabbit, Cat ]

-}
check : Decoder a -> a -> Decoder b -> Decoder b
check checkDecoder expectedVal actualDecoder =
    checkDecoder
        |> andThen
            (\actual ->
                if actual == expectedVal then
                    actualDecoder

                else
                    fail "Verification failed"
            )



-- Mapping and chaining


{-| Useful for transforming decoders.

    """ "foo" """
        |> decodeString (map String.toUpper string)
    --> Success "FOO"

-}
map : (a -> b) -> Decoder a -> Decoder b
map f (Decoder decoderFn) =
    Decoder <|
        \json ->
            Tuple.mapSecond (Result.map (mapAcc f)) (decoderFn json)


{-| Chain decoders where one decoder depends on the value of another decoder.
-}
andThen : (a -> Decoder b) -> Decoder a -> Decoder b
andThen toDecoderB (Decoder decoderFnA) =
    Decoder <|
        \json ->
            case decoderFnA json of
                ( annVal, Ok accA ) ->
                    let
                        (Decoder decoderFnB) =
                            toDecoderB accA.value

                        ( annValB, res ) =
                            decoderFnB annVal
                    in
                    ( annValB, Result.map (\accB -> { accB | warnings = accA.warnings ++ accB.warnings }) res )

                ( annVal, Err e ) ->
                    ( annVal, Err e )


{-| Combine 2 decoders.
-}
map2 : (a -> b -> c) -> Decoder a -> Decoder b -> Decoder c
map2 f (Decoder decoderFnA) (Decoder decoderFnB) =
    Decoder <|
        \json ->
            case decoderFnA json of
                ( annVal, Ok accA ) ->
                    case decoderFnB annVal of
                        ( annValB, Ok accB ) ->
                            ( annValB
                            , Ok
                                { value = f accA.value accB.value
                                , warnings = accA.warnings ++ accB.warnings
                                }
                            )

                        ( annValB, Err e ) ->
                            ( annValB, Err e )

                ( annVal, Err e ) ->
                    case decoderFnB annVal of
                        ( annValB, Ok _ ) ->
                            ( annValB, Err e )

                        ( annValB, Err e2 ) ->
                            ( annValB, Err <| Nonempty.append e e2 )


{-| Decode an argument and provide it to a function in a decoder.

    decoder : Decoder String
    decoder =
        succeed (String.repeat)
            |> andMap (field "count" int)
            |> andMap (field "val" string)


    """ { "val": "hi", "count": 3 } """
        |> decodeString decoder
    --> Success "hihihi"

-}
andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    map2 (|>)


{-| Combine 3 decoders.
-}
map3 :
    (a -> b -> c -> d)
    -> Decoder a
    -> Decoder b
    -> Decoder c
    -> Decoder d
map3 f decoderA decoderB decoderC =
    map f decoderA
        |> andMap decoderB
        |> andMap decoderC


{-| Combine 4 decoders.
-}
map4 :
    (a -> b -> c -> d -> e)
    -> Decoder a
    -> Decoder b
    -> Decoder c
    -> Decoder d
    -> Decoder e
map4 f decoderA decoderB decoderC decoderD =
    map f decoderA
        |> andMap decoderB
        |> andMap decoderC
        |> andMap decoderD


{-| Combine 5 decoders.
-}
map5 :
    (a -> b -> c -> d -> e -> f)
    -> Decoder a
    -> Decoder b
    -> Decoder c
    -> Decoder d
    -> Decoder e
    -> Decoder f
map5 f decoderA decoderB decoderC decoderD decoderE =
    map f decoderA
        |> andMap decoderB
        |> andMap decoderC
        |> andMap decoderD
        |> andMap decoderE


{-| Combine 6 decoders.
-}
map6 :
    (a -> b -> c -> d -> e -> f -> g)
    -> Decoder a
    -> Decoder b
    -> Decoder c
    -> Decoder d
    -> Decoder e
    -> Decoder f
    -> Decoder g
map6 f decoderA decoderB decoderC decoderD decoderE decoderF =
    map f decoderA
        |> andMap decoderB
        |> andMap decoderC
        |> andMap decoderD
        |> andMap decoderE
        |> andMap decoderF


{-| Combine 7 decoders.
-}
map7 :
    (a -> b -> c -> d -> e -> f -> g -> h)
    -> Decoder a
    -> Decoder b
    -> Decoder c
    -> Decoder d
    -> Decoder e
    -> Decoder f
    -> Decoder g
    -> Decoder h
map7 f decoderA decoderB decoderC decoderD decoderE decoderF decoderG =
    map f decoderA
        |> andMap decoderB
        |> andMap decoderC
        |> andMap decoderD
        |> andMap decoderE
        |> andMap decoderF
        |> andMap decoderG


{-| Combine 8 decoders.
-}
map8 :
    (a -> b -> c -> d -> e -> f -> g -> h -> i)
    -> Decoder a
    -> Decoder b
    -> Decoder c
    -> Decoder d
    -> Decoder e
    -> Decoder f
    -> Decoder g
    -> Decoder h
    -> Decoder i
map8 f decoderA decoderB decoderC decoderD decoderE decoderF decoderG decoderH =
    map f decoderA
        |> andMap decoderB
        |> andMap decoderC
        |> andMap decoderD
        |> andMap decoderE
        |> andMap decoderF
        |> andMap decoderG
        |> andMap decoderH



-- Internal stuff


type AnnotatedValue
    = String Bool String
    | Number Bool Float
    | Bool Bool Bool
    | Null Bool
    | Array Bool (List ( Bool, AnnotatedValue ))
    | Object Bool (List ( Bool, String, AnnotatedValue ))


expected : ExpectedType -> AnnotatedValue -> ( AnnotatedValue, Result Errors a )
expected expectedType json =
    encode json
        |> Expected expectedType
        |> Here
        |> Nonempty.fromElement
        |> Err
        |> Tuple.pair json


decode : Value -> Result Decode.Error AnnotatedValue
decode =
    Decode.decodeValue annotatedDecoder


annotatedDecoder : Decode.Decoder AnnotatedValue
annotatedDecoder =
    Decode.oneOf
        [ Decode.map (String False) Decode.string
        , Decode.map (Number False) Decode.float
        , Decode.map (Bool False) Decode.bool
        , Decode.null (Null False)
        , Decode.map (Array False)
            (Decode.list <|
                Decode.map (Tuple.pair False)
                    (Decode.lazy <| \_ -> annotatedDecoder)
            )
        , Decode.map
            (Object False)
            (Decode.map
                (List.map (\( k, v ) -> ( False, k, v )))
                (Decode.keyValuePairs <| Decode.lazy <| \_ -> annotatedDecoder)
            )
        ]


encode : AnnotatedValue -> Value
encode v =
    case v of
        String _ val ->
            Encode.string val

        Number _ val ->
            Encode.float val

        Bool _ val ->
            Encode.bool val

        Null _ ->
            Encode.null

        Array _ values ->
            Encode.list (Tuple.second >> encode) values

        Object _ kvPairs ->
            List.map (\( _, k, v_ ) -> ( k, encode v_ )) kvPairs
                |> Encode.object


gatherWarnings : AnnotatedValue -> List (Located Warning)
gatherWarnings json =
    case json of
        String False _ ->
            [ Here <| UnusedValue <| encode json ]

        Number False _ ->
            [ Here <| UnusedValue <| encode json ]

        Bool False _ ->
            [ Here <| UnusedValue <| encode json ]

        Null False ->
            [ Here <| UnusedValue <| encode json ]

        Array False _ ->
            [ Here <| UnusedValue <| encode json ]

        Object False _ ->
            [ Here <| UnusedValue <| encode json ]

        Array _ values ->
            values
                |> List.indexedMap
                    (\idx ( used, val ) ->
                        if used then
                            case gatherWarnings val of
                                [] ->
                                    []

                                x :: xs ->
                                    [ AtIndex idx <| Nonempty x xs ]

                        else
                            [ Here (UnusedIndex idx) ]
                    )
                |> List.concat

        Object _ kvPairs ->
            kvPairs
                |> List.concatMap
                    (\( used, key, val ) ->
                        if used then
                            case gatherWarnings val of
                                [] ->
                                    []

                                x :: xs ->
                                    [ InField key <| Nonempty x xs ]

                        else
                            [ Here (UnusedField key) ]
                    )

        _ ->
            []


markUsed : AnnotatedValue -> AnnotatedValue
markUsed annotatedValue =
    case annotatedValue of
        String _ val ->
            String True val

        Number _ val ->
            Number True val

        Bool _ val ->
            Bool True val

        Null _ ->
            Null True

        Array _ values ->
            Array True (List.map (\( _, v ) -> ( True, markUsed v )) values)

        Object _ values ->
            Object True (List.map (\( _, f, v ) -> ( True, f, markUsed v )) values)



---


{-| Interpret a decode result in a strict way, lifting warnings to errors.

    import List.Nonempty as Nonempty
    import Json.Decode.Exploration.Located exposing (Located(..))
    import Json.Encode as Encode


    """ ["foo"] """
        |> decodeString isArray
        |> strict
    --> (Here <| Failure "Unused index: 0" Nothing)
    -->   |> (Err << Nonempty.fromElement)


    """ null """
        |> decodeString (null "cool")
        |> strict
    --> Ok "cool"

    """ { "foo": "bar" } """
        |> decodeString isObject
        |> strict
    --> (Here <| Failure "Unused field: foo" Nothing)
    -->   |> (Err << Nonempty.fromElement)

Bad JSON will also result in a `Failure`, with `Nothing` as the actual value:

    """ foobar """
        |> decodeString string
        |> strict
    --> (Here <| Failure "Invalid JSON" Nothing)
    -->   |> (Err << Nonempty.fromElement)

Errors will still be errors, of course.

    """ null """
        |> decodeString string
        |> strict
    --> (Here <| Expected TString Encode.null)
    -->   |> (Err << Nonempty.fromElement)

-}
strict : DecodeResult a -> Result Errors a
strict res =
    case res of
        Errors e ->
            Err e

        BadJson ->
            Err <| Nonempty.fromElement <| Here <| Failure "Invalid JSON" Nothing

        WithWarnings w _ ->
            Err <| warningsToErrors w

        Success v ->
            Ok v


warningsToErrors : Warnings -> Errors
warningsToErrors =
    Nonempty.map (Located.map warningToError)


warningToError : Warning -> Error
warningToError warning =
    case warning of
        UnusedValue v ->
            Failure "Unused value" (Just v)

        UnusedField name ->
            Failure ("Unused field: " ++ name) Nothing

        UnusedIndex idx ->
            Failure ("Unused index: " ++ String.fromInt idx) Nothing

        Warning w v ->
            Failure w (Just v)


{-| Stringifies warnings to a human readable string.
-}
warningsToString : Warnings -> String
warningsToString warnings =
    "While I was able to decode this JSON successfully, I did produce one or more warnings:"
        :: ""
        :: Located.toString warningToString warnings
        |> List.map String.trimRight
        |> String.join "\n"


warningToString : Warning -> List String
warningToString warning =
    let
        ( message, val ) =
            case warning of
                Warning message_ val_ ->
                    ( message_, Just val_ )

                UnusedValue val_ ->
                    ( "Unused value:", Just val_ )

                UnusedField name ->
                    ( "Unused field: " ++ name, Nothing )

                UnusedIndex idx ->
                    ( "Unused index: " ++ String.fromInt idx, Nothing )
    in
    case val of
        Nothing ->
            [ message ]

        Just v ->
            message :: "" :: indent (jsonLines v)


indent : List String -> List String
indent =
    List.map ((++) "  ")


jsonLines : Value -> List String
jsonLines =
    Encode.encode 2 >> String.lines


{-| Stringifies errors to a human readable string.
-}
errorsToString : Errors -> String
errorsToString errors =
    "I encountered some errors while decoding this JSON:"
        :: ""
        :: errorsToStrings errors
        |> List.map String.trimRight
        |> String.join "\n"


errorsToStrings : Errors -> List String
errorsToStrings errors =
    Located.toString errorToString errors


errorToString : Error -> List String
errorToString error =
    case error of
        Failure failure json ->
            case json of
                Just val ->
                    failure
                        :: ""
                        :: (indent <| jsonLines val)

                Nothing ->
                    [ failure ]

        Expected expectedType actualValue ->
            ("I expected "
                ++ expectedTypeToString expectedType
                ++ " here, but instead found this value:"
            )
                :: ""
                :: (indent <| jsonLines actualValue)

        BadOneOf errors ->
            case errors of
                [] ->
                    [ "I encountered a `oneOf` without any options." ]

                _ ->
                    "I encountered multiple issues:"
                        :: ""
                        :: intercalateMap "" errorsToStrings errors


intercalateMap : b -> (a -> List b) -> List a -> List b
intercalateMap sep toList xs =
    List.map toList xs
        |> List.intersperse [ sep ]
        |> List.concat


expectedTypeToString : ExpectedType -> String
expectedTypeToString expectedType =
    case expectedType of
        TString ->
            "a string"

        TInt ->
            "an integer number"

        TNumber ->
            "a number"

        TNull ->
            "null"

        TBool ->
            "a boolean"

        TArray ->
            "an array"

        TObject ->
            "an object"

        TArrayIndex idx ->
            "an array with index " ++ String.fromInt idx

        TObjectField aField ->
            "an object with a field '" ++ aField ++ "'"


stripAnnotatedValue : AnnotatedValue -> Value
stripAnnotatedValue annVal =
    case annVal of
        String True v ->
            Encode.string v

        String False _ ->
            Encode.string ""

        Number True v ->
            Encode.float v

        Number False _ ->
            Encode.float 0

        Bool _ v ->
            Encode.bool v

        Null _ ->
            Encode.null

        Array True entries ->
            minifyArray entries

        Array False _ ->
            Encode.list identity []

        Object True entries ->
            minifyObject entries

        Object False _ ->
            Encode.object []


minifyArray : List ( Bool, AnnotatedValue ) -> Value
minifyArray entries =
    entries
        |> List.filterMap
            (\( used, entry ) ->
                if used then
                    Just (stripAnnotatedValue entry)

                else
                    Nothing
            )
        |> Encode.list identity


minifyObject : List ( Bool, String, AnnotatedValue ) -> Value
minifyObject entries =
    entries
        |> List.filterMap
            (\( used, f, entry ) ->
                if used then
                    Just ( f, stripAnnotatedValue entry )

                else
                    Nothing
            )
        |> Encode.object
