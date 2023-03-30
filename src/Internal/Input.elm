module Internal.Input exposing
    ( Hidden(..)
    , Input(..)
    , InputType(..)
    , Options(..)
    , inputTypeToString
    )


type InputType
    = Text
    | Number
      -- TODO should range have arguments for initial, min, and max?
    | Range
    | Radio
      -- TODO should submit be a special type, or an Input type?
      -- TODO have an option for a submit with a name/value?
    | Date
    | Time
    | Checkbox
    | Tel
    | Search
    | Password
    | Email
    | Url
    | Textarea { rows : Maybe Int, cols : Maybe Int }


inputTypeToString : InputType -> String
inputTypeToString inputType =
    case inputType of
        Text ->
            "text"

        Textarea _ ->
            "text"

        Number ->
            "number"

        Range ->
            "range"

        Radio ->
            "radio"

        Date ->
            "date"

        Time ->
            "time"

        Checkbox ->
            "checkbox"

        Tel ->
            "tel"

        Search ->
            "search"

        Password ->
            "password"

        Email ->
            "email"

        Url ->
            "url"


type Input
    = Input InputType


type Hidden
    = Hidden


type Options a
    = Options (String -> Maybe a) (List String)
