module BackendTask.Time exposing
    ( now
    , zone, zoneFor, zoneByName
    , DateRange, withinYears, withinRange, between
    )

{-|

@docs now

@docs zone, zoneFor, zoneByName

@docs DateRange, withinYears, withinRange, between

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Date exposing (Date)
import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| Gives a `Time.Posix` of when the `BackendTask` executes.

    type alias Data =
        { time : Time.Posix
        }

    data : BackendTask FatalError Data
    data =
        BackendTask.map Data
            BackendTask.Time.now

It's better to use [`Server.Request.requestTime`](Server-Request#requestTime) or `Pages.builtAt` when those are the semantics
you are looking for. `requestTime` gives you a single reliable and consistent time for when the incoming HTTP request was received in
a server-rendered Route or server-rendered API Route. `Pages.builtAt` gives a single reliable and consistent time when the
site was built.

`BackendTask.Time.now` gives you the time that it happened to execute, which might give you what you need, but be
aware that the time you get is dependent on how BackendTask's are scheduled and executed internally in elm-pages, and
its best to avoid depending on that variation when possible.

-}
now : BackendTask error Time.Posix
now =
    BackendTask.Internal.Request.request
        { name = "now"
        , body =
            BackendTask.Http.jsonBody Encode.null
        , expect =
            BackendTask.Http.expectJson
                (Decode.int |> Decode.map Time.millisToPosix)
        }


{-| Get the server's local [`Time.Zone`](https://package.elm-lang.org/packages/elm/time/latest/Time#Zone)
with DST transitions covering 50 years in each direction from the current time.

    import BackendTask.Time

    myZone : BackendTask error Time.Zone
    myZone =
        BackendTask.Time.zone

This is the simplest way to get a timezone with correct DST handling. The 50-year default
covers the vast majority of use cases.

**Performance:** Computing timezone transitions takes roughly 35-80ms depending on how many
DST transitions the timezone has (timezones without DST like UTC or Asia/Kolkata are fastest).
If you need a narrower or wider range, use [`zoneFor`](#zoneFor) with a [`DateRange`](#DateRange).
For reference, `withinYears 5` takes ~10ms, `withinYears 50` (this default) ~40-80ms, and
`withinYears 100` ~70-130ms.

**Note:** This returns the timezone of the _server_ (or build machine), not the client's browser timezone.
This makes it particularly useful for scripting and build-time tasks where you want to format dates in
the server's local time. It is unlikely to be useful for resolving timezones for server-rendered routes,
since the server's timezone will generally not match the end user's timezone.

-}
zone : BackendTask error Time.Zone
zone =
    zoneFor (withinYears 50)


{-| Get the server's local [`Time.Zone`](https://package.elm-lang.org/packages/elm/time/latest/Time#Zone)
with DST transitions for a specific date range.

    import BackendTask.Time exposing (between)
    import Date
    import Time

    myZone : BackendTask error Time.Zone
    myZone =
        BackendTask.Time.zoneFor
            (between
                { since = Date.fromCalendarDate 2020 Time.Jan 1
                , until = Date.fromCalendarDate 2030 Time.Dec 31
                }
            )

Use this instead of [`zone`](#zone) when you want to limit the range of DST transition data,
for example to a narrower window around the dates you need.

**Note:** This returns the timezone of the _server_ (or build machine), not the client's browser timezone.

-}
zoneFor : DateRange -> BackendTask error Time.Zone
zoneFor dateRange =
    BackendTask.Internal.Request.request
        { name = "timezone"
        , body =
            BackendTask.Http.jsonBody
                (encodeDateRange Nothing dateRange)
        , expect =
            BackendTask.Http.expectJson zoneDecoder
        }


{-| Get a [`Time.Zone`](https://package.elm-lang.org/packages/elm/time/latest/Time#Zone) for a specific
IANA timezone (e.g. `"America/New_York"`, `"Europe/London"`, `"Asia/Tokyo"`) with DST transitions for
the given date range.

    import BackendTask.Time exposing (withinYears)

    newYorkZone : BackendTask error Time.Zone
    newYorkZone =
        BackendTask.Time.zoneByName "America/New_York" (withinYears 100)

This is useful for formatting dates in a known timezone regardless of what timezone the server is running in.
For example, a blog built on a CI server (typically UTC) can format post dates in the author's local timezone.

An invalid timezone name (e.g. `"Foo/Bar"`) will result in a `FatalError`.

-}
zoneByName : String -> DateRange -> BackendTask error Time.Zone
zoneByName timeZoneId dateRange =
    BackendTask.Internal.Request.request
        { name = "timezone"
        , body =
            BackendTask.Http.jsonBody
                (encodeDateRange (Just timeZoneId) dateRange)
        , expect =
            BackendTask.Http.expectJson zoneDecoder
        }


{-| A date range that specifies which period of time to include timezone transition data for.
-}
type DateRange
    = Relative { yearsAgo : Int, yearsAhead : Int }
    | Absolute { sinceMs : Int, untilMs : Int }


{-| A symmetric date range: N years before and after the current time.

    BackendTask.Time.zoneFor (BackendTask.Time.withinYears 5)

-}
withinYears : Int -> DateRange
withinYears n =
    Relative { yearsAgo = n, yearsAhead = n }


{-| An asymmetric date range relative to the current time.

    BackendTask.Time.zoneFor (BackendTask.Time.withinRange { yearsAgo = 10, yearsAhead = 2 })

-}
withinRange : { yearsAgo : Int, yearsAhead : Int } -> DateRange
withinRange =
    Relative


{-| An exact date range using [`Date`](https://package.elm-lang.org/packages/justinmimbs/date/latest/Date) values.

    import Date
    import Time

    BackendTask.Time.zoneFor
        (BackendTask.Time.between
            { since = Date.fromCalendarDate 2020 Time.Jan 1
            , until = Date.fromCalendarDate 2030 Time.Dec 31
            }
        )

-}
between : { since : Date, until : Date } -> DateRange
between { since, until } =
    Absolute
        { sinceMs = dateToEpochMs since
        , untilMs = dateToEpochMs until
        }


encodeDateRange : Maybe String -> DateRange -> Encode.Value
encodeDateRange maybeTzId dateRange =
    let
        tzField =
            case maybeTzId of
                Just tzId ->
                    [ ( "tzId", Encode.string tzId ) ]

                Nothing ->
                    []

        rangeFields =
            case dateRange of
                Relative { yearsAgo, yearsAhead } ->
                    [ ( "yearsAgo", Encode.int yearsAgo )
                    , ( "yearsAhead", Encode.int yearsAhead )
                    ]

                Absolute { sinceMs, untilMs } ->
                    [ ( "sinceMs", Encode.int sinceMs )
                    , ( "untilMs", Encode.int untilMs )
                    ]
    in
    Encode.object (tzField ++ rangeFields)


dateToEpochMs : Date -> Int
dateToEpochMs date =
    (Date.toRataDie date - 719163) * 86400000


zoneDecoder : Decode.Decoder Time.Zone
zoneDecoder =
    Decode.map2 Time.customZone
        (Decode.field "defaultOffset" Decode.int)
        (Decode.field "eras"
            (Decode.list
                (Decode.map2 (\start offset -> { start = start, offset = offset })
                    (Decode.field "start" Decode.int)
                    (Decode.field "offset" Decode.int)
                )
            )
        )
