module Result.Extra exposing (combine, isOk, merge)


isOk : Result x a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False


merge : Result a a -> a
merge r =
    case r of
        Ok rr ->
            rr

        Err rr ->
            rr


combine : List (Result x a) -> Result x (List a)
combine =
    List.foldr (Result.map2 (::)) (Ok [])
