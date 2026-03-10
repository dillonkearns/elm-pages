module Test.BackendTask.Time exposing
    ( TimeZone
    , utc, fixedOffsetZone, customTimeZone
    , withTimeZone, withTimeZoneByName
    )

{-| Configure virtual time zones for BackendTask tests.


## TimeZone

@docs TimeZone


## Constructors

@docs utc, fixedOffsetZone, customTimeZone


## Test Setup

@docs withTimeZone, withTimeZoneByName

-}

import Test.BackendTask.Internal as Internal exposing (TestSetup)


{-| Represents a time zone for use in tests with [`withTimeZone`](#withTimeZone) and
[`withTimeZoneByName`](#withTimeZoneByName). Create values with [`utc`](#utc),
[`fixedOffsetZone`](#fixedOffsetZone), or [`customTimeZone`](#customTimeZone).
-}
type TimeZone
    = TimeZone Internal.TimeZoneData


{-| UTC time zone (offset 0).

    import Test.BackendTask as BackendTaskTest
    import Test.BackendTask.Time as BackendTaskTime

    BackendTaskTest.init
        |> BackendTaskTime.withTimeZone BackendTaskTime.utc

-}
utc : TimeZone
utc =
    TimeZone { defaultOffset = 0, eras = [] }


{-| A time zone with a fixed offset in minutes from UTC. Negative values are
west of UTC (e.g., -300 for US Eastern Standard Time).

    import Test.BackendTask.Time as BackendTaskTime

    BackendTaskTime.fixedOffsetZone -300

-}
fixedOffsetZone : Int -> TimeZone
fixedOffsetZone offsetMinutes =
    TimeZone { defaultOffset = offsetMinutes, eras = [] }


{-| A time zone with a default offset and a list of era transitions. Each era
specifies a start time (milliseconds since epoch) and its UTC offset in minutes.

    import Test.BackendTask.Time as BackendTaskTime

    BackendTaskTime.customTimeZone -300
        [ { start = 1710057600000, offset = -240 } ]

-}
customTimeZone : Int -> List { start : Int, offset : Int } -> TimeZone
customTimeZone defaultOffset eras =
    TimeZone { defaultOffset = defaultOffset, eras = eras }


{-| Set the default virtual time zone for `BackendTask.Time.zone` and
`BackendTask.Time.zoneFor`.

    import Test.BackendTask as BackendTaskTest
    import Test.BackendTask.Time as BackendTaskTime

    BackendTaskTest.init
        |> BackendTaskTime.withTimeZone BackendTaskTime.utc

-}
withTimeZone : TimeZone -> TestSetup -> TestSetup
withTimeZone (TimeZone tz) =
    Internal.withTimeZone tz


{-| Register a named time zone for `BackendTask.Time.zoneByName` and
`BackendTask.Time.zoneByNameFor`.

    import Test.BackendTask as BackendTaskTest
    import Test.BackendTask.Time as BackendTaskTime

    BackendTaskTest.init
        |> BackendTaskTime.withTimeZoneByName "America/Chicago"
            (BackendTaskTime.fixedOffsetZone -360)

-}
withTimeZoneByName : String -> TimeZone -> TestSetup -> TestSetup
withTimeZoneByName name (TimeZone tz) =
    Internal.withTimeZoneByName name tz
