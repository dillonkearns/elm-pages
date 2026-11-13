import { describe, it, expect } from "vitest";
import {
  runTimezone,
  getTimezoneDataIntl,
  getTimezoneDataTemporal,
} from "../src/timezone.js";

const since = Date.UTC(2020, 0, 1);
const until = Date.UTC(2030, 0, 1);

function request(args) {
  return { body: { args: [args] } };
}

const hasTemporalTransitions =
  typeof globalThis.Temporal?.ZonedDateTime?.prototype
    ?.getTimeZoneTransition === "function";

const zones = [
  "America/New_York",
  "Europe/London",
  "Australia/Lord_Howe",
  "Asia/Kolkata",
  "Africa/Casablanca",
  "UTC",
];

describe("runTimezone", () => {
  it("returns the daylight saving changes for a named zone", () => {
    const result = runTimezone(
      request({
        tzId: "America/New_York",
        sinceMs: Date.UTC(2024, 0, 1),
        untilMs: Date.UTC(2025, 0, 1),
      })
    );

    expect(result).toEqual({
      defaultOffset: -300,
      eras: [
        { start: Date.UTC(2024, 10, 3, 6) / 60000, offset: -300 },
        { start: Date.UTC(2024, 2, 10, 7) / 60000, offset: -240 },
      ],
    });
  });

  it("returns no changes for a zone without daylight saving", () => {
    expect(
      runTimezone(
        request({ tzId: "Asia/Kolkata", sinceMs: since, untilMs: until })
      )
    ).toEqual({ defaultOffset: 330, eras: [] });
  });

  it("uses the system zone when no name is given", () => {
    const result = runTimezone(request({ sinceMs: since, untilMs: until }));

    expect(typeof result.defaultOffset).toBe("number");
    expect(Array.isArray(result.eras)).toBe(true);
  });

  it("rejects a zone name that does not exist", () => {
    expect(() =>
      runTimezone(request({ tzId: "Foo/Bar", sinceMs: since, untilMs: until }))
    ).toThrow(expect.objectContaining({ title: "Invalid Timezone" }));
  });
});

describe("getTimezoneDataIntl", () => {
  it("finds a change in the last days of the range", () => {
    const result = getTimezoneDataIntl(
      "America/New_York",
      Date.UTC(2024, 0, 1),
      Date.UTC(2024, 10, 3, 12)
    );

    expect(result.eras[0]).toEqual({
      start: Date.UTC(2024, 10, 3, 6) / 60000,
      offset: -300,
    });
  });
});

// Liberia was 44 minutes and 30 seconds behind UTC until 1972. Elm only
// accepts whole minutes.
describe("zones with offsets that are not whole minutes", () => {
  const liberiaSince = Date.UTC(1960, 0, 1);
  const liberiaUntil = Date.UTC(1980, 0, 1);
  const expected = {
    defaultOffset: -44,
    eras: [
      { start: Math.floor(Date.UTC(1972, 0, 7, 0, 44, 30) / 60000), offset: 0 },
    ],
  };

  it("rounds to whole minutes with Intl", () => {
    expect(
      getTimezoneDataIntl("Africa/Monrovia", liberiaSince, liberiaUntil)
    ).toEqual(expected);
  });

  it.runIf(hasTemporalTransitions)(
    "rounds to whole minutes with Temporal",
    () => {
      expect(
        getTimezoneDataTemporal("Africa/Monrovia", liberiaSince, liberiaUntil)
      ).toEqual(expected);
    }
  );
});

describe.runIf(hasTemporalTransitions)("getTimezoneDataTemporal", () => {
  it.each(zones)("matches the Intl fallback for %s", (tzId) => {
    expect(getTimezoneDataTemporal(tzId, since, until)).toEqual(
      getTimezoneDataIntl(tzId, since, until)
    );
  });
});
