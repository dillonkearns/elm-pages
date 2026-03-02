import { describe, it, expect } from "vitest";
import {
  generatePagesDbModule,
  generatePagesDbSeedModule,
} from "../src/commands/shared.js";

describe("Pages.Db codegen", () => {
  it("uses Pages.DbSeed for empty db.bin fallback", () => {
    const generated = generatePagesDbModule("abc123");
    expect(generated).toContain("import Pages.DbSeed");
    expect(generated).toContain("BackendTask.succeed Pages.DbSeed.seedCurrent");
    expect(generated).not.toContain("BackendTask.succeed Db.init");
  });

  it("exposes path-aware API variants for custom db file locations", () => {
    const generated = generatePagesDbModule("abc123");
    expect(generated).toContain(
      "module Pages.Db exposing (get, getAt, update, updateAt, transaction, transactionAt)"
    );
    expect(generated).toContain('getAt "db.bin"');
    expect(generated).toContain('updateAt "db.bin" fn');
    expect(generated).toContain('transactionAt "db.bin" fn');
    expect(generated).toContain('( "path", Encode.string dbPath )');
  });
});

describe("Pages.DbSeed codegen", () => {
  it("uses Db.init for schema V1", () => {
    const generated = generatePagesDbSeedModule(1);
    expect(generated).toContain("module Pages.DbSeed exposing (seedCurrent)");
    expect(generated).toContain("seedCurrent : Db.Db");
    expect(generated).toContain("Db.init");
  });

  it("chains from Db.V1.init for schema V3 using seed functions", () => {
    const generated = generatePagesDbSeedModule(3);
    expect(generated).toContain("import Db.V1");
    expect(generated).toContain("import Db.Migrate.V2 as MigrateV2");
    expect(generated).toContain("import Db.Migrate.V3 as MigrateV3");
    expect(generated).toContain("Db.V1.init");
    expect(generated).toContain("|> MigrateV2.seed");
    expect(generated).toContain("|> MigrateV3.seed");
  });
});
