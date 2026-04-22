module Test.PagesProgram.Session exposing
    ( Session
    , empty, withValue, withFlash
    )

{-| Build a session payload to seed into a signed session cookie. Pair with
[`Test.PagesProgram.CookieJar.setSession`](Test-PagesProgram-CookieJar#setSession)
to place the signed value into the cookie jar for a test.

    import Test.BackendTask as BackendTaskTest
    import Test.PagesProgram.CookieJar as CookieJar
    import Test.PagesProgram.Session as Session

    BackendTaskTest.init
        |> CookieJar.withCookies
            (CookieJar.empty
                |> CookieJar.setSession "mysession"
                    (Session.empty
                        |> Session.withValue "userId" "42"
                        |> Session.withFlash "greeting" "Welcome back!"
                    )
            )

@docs Session


## Building

@docs empty, withValue, withFlash

-}

import Test.BackendTask.Internal as Internal


{-| A session payload: a set of persistent session values and one-shot flash
values. Mirrors the shape produced by [`Server.Session`](Server-Session) at
runtime.
-}
type alias Session =
    Internal.Session


{-| An empty session with no values.
-}
empty : Session
empty =
    Internal.session


{-| Add a persistent session value.
-}
withValue : String -> String -> Session -> Session
withValue =
    Internal.withSessionValue


{-| Add a flash session value. Flash values are available on the next request
only, matching [`Server.Session.withFlash`](Server-Session#withFlash).
-}
withFlash : String -> String -> Session -> Session
withFlash =
    Internal.withFlashValue
