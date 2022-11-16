module Result.Extra exposing (isOk)


isOk : Result x a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False
