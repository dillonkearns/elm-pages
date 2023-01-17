module Pages.Internal.FatalError exposing (FatalError(..))


type FatalError
    = FatalError { title : String, body : String }
