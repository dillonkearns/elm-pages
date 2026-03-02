import { describe, it, expect } from "vitest";
import {
  generatePagesDbModule,
  generatePagesDbSeedModule,
} from "../src/commands/shared.js";

describe("Pages.Db codegen", () => {
  it("uses Pages.DbSeed for empty db.bin fallback", () => {
    const generated = generatePagesDbModule("abc123", 1);
    expect(generated).toContain("import Pages.DbSeed");
    expect(generated).toContain("BackendTask.succeed Pages.DbSeed.seedCurrent");
    expect(generated).not.toContain("BackendTask.succeed Db.init");
  });

  it("exposes session-based API for custom db file locations", () => {
    const generated = generatePagesDbModule("abc123", 3);
    expect(generated).toContain(
      "module Pages.Db exposing (Session, default, open, get, update, transaction)"
    );
    expect(generated).toContain("type Session");
    expect(generated).toContain("open : FilePath -> Session");
    expect(generated).toContain("default : Session");
    expect(generated).toContain("get : Session -> BackendTask FatalError Db.Db");
    expect(generated).toContain(
      "update : Session -> (Db.Db -> Db.Db) -> BackendTask FatalError ()"
    );
    expect(generated).toContain('( "hash", Encode.string schemaHash )');
    expect(generated).toContain("internalRequest \"db-read-meta\"");
    expect(generated).toContain("internalRequest \"db-migrate-write\"");
    expect(generated).toContain("internalRequest \"db-lock-acquire\"");
    expect(generated).toContain("sessionFields : Session -> List ( String, Encode.Value )");
    expect(generated).not.toContain("getAt :");
    expect(generated).not.toContain("updateAt :");
    expect(generated).not.toContain("transactionAt :");
    expect(generated).toContain("migrateFromV1");
    expect(generated).toContain("migrateFromVersion session version bytes");
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
