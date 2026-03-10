module TimezoneTests exposing (run)

import BackendTask.Time exposing (between, withinRange, withinYears)
import BackendTaskTest exposing (testTask, testScript)
import Date
import Expect
import Pages.Script exposing (Script)
import Time


{-| These tests should be run with TZ=America/New\_York to get deterministic results.

America/New\_York is UTC-5 (EST) in winter and UTC-4 (EDT) in summer.

-}
run : Script
run =
    testScript "Timezone"
        [ BackendTask.Time.zone
            |> testTask "zone (default): winter hour (EST = UTC-5)"
                (\z ->
                    -- Jan 1, 2024 00:00 UTC = Dec 31, 2023 19:00 EST (UTC-5)
                    Time.toHour z (Time.millisToPosix 1704067200000)
                        |> Expect.equal 19
                )
        , BackendTask.Time.zone
            |> testTask "zone (default): summer hour (EDT = UTC-4)"
                (\z ->
                    -- Jul 1, 2024 12:00 UTC = Jul 1, 2024 08:00 EDT (UTC-4)
                    Time.toHour z (Time.millisToPosix 1719835200000)
                        |> Expect.equal 8
                )
        , BackendTask.Time.zoneFor (withinRange { yearsAgo = 10, yearsAhead = 2 })
            |> testTask "zone withinRange: asymmetric range works"
                (\z ->
                    -- Jan 1, 2024 00:00 UTC = Dec 31, 2023 19:00 EST (UTC-5)
                    Time.toHour z (Time.millisToPosix 1704067200000)
                        |> Expect.equal 19
                )
        , BackendTask.Time.zoneFor
            (between
                { since = Date.fromCalendarDate 2020 Time.Jan 1
                , until = Date.fromCalendarDate 2030 Time.Dec 31
                }
            )
            |> testTask "zone between: winter offset (EST = UTC-5)"
                (\z ->
                    -- Jan 15, 2024 18:00 UTC = Jan 15, 2024 13:00 EST
                    Time.toHour z (Time.millisToPosix 1705341600000)
                        |> Expect.equal 13
                )
        , BackendTask.Time.zoneFor
            (between
                { since = Date.fromCalendarDate 2020 Time.Jan 1
                , until = Date.fromCalendarDate 2030 Time.Dec 31
                }
            )
            |> testTask "zone between: summer offset (EDT = UTC-4)"
                (\z ->
                    -- Jul 15, 2024 18:00 UTC = Jul 15, 2024 14:00 EDT
                    Time.toHour z (Time.millisToPosix 1721066400000)
                        |> Expect.equal 14
                )
        , BackendTask.Time.zoneFor
            (between
                { since = Date.fromCalendarDate 2024 Time.Mar 1
                , until = Date.fromCalendarDate 2024 Time.Apr 30
                }
            )
            |> testTask "zone between: DST spring forward transition captured"
                (\z ->
                    -- Mar 10, 2024 is when America/New_York springs forward
                    -- Mar 10, 2024 08:00 UTC = Mar 10, 2024 04:00 EDT (UTC-4, after spring forward)
                    Time.toHour z (Time.millisToPosix 1710057600000)
                        |> Expect.equal 4
                )

        -- zoneByName tests (don't depend on TZ env var)
        , BackendTask.Time.zoneByName "America/Chicago"
            |> testTask "zoneByName: Chicago winter (CST = UTC-6)"
                (\z ->
                    -- Jan 1, 2024 00:00 UTC = Dec 31, 2023 18:00 CST (UTC-6)
                    Time.toHour z (Time.millisToPosix 1704067200000)
                        |> Expect.equal 18
                )
        , BackendTask.Time.zoneByName "America/Chicago"
            |> testTask "zoneByName: Chicago summer (CDT = UTC-5)"
                (\z ->
                    -- Jul 1, 2024 12:00 UTC = Jul 1, 2024 07:00 CDT (UTC-5)
                    Time.toHour z (Time.millisToPosix 1719835200000)
                        |> Expect.equal 7
                )
        , BackendTask.Time.zoneByNameFor "Asia/Kolkata"
            (between
                { since = Date.fromCalendarDate 2020 Time.Jan 1
                , until = Date.fromCalendarDate 2030 Time.Dec 31
                }
            )
            |> testTask "zoneByNameFor: Kolkata fixed offset (UTC+5:30)"
                (\z ->
                    -- Jan 1, 2024 00:00 UTC = Jan 1, 2024 05:30 IST (UTC+5:30)
                    Time.toHour z (Time.millisToPosix 1704067200000)
                        |> Expect.equal 5
                )
        , BackendTask.Time.zoneByName "UTC"
            |> testTask "zoneByName: UTC is always 0 offset"
                (\z ->
                    Time.toHour z (Time.millisToPosix 1704067200000)
                        |> Expect.equal 0
                )
        ]
