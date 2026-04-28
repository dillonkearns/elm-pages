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

  it("exposes connection-based API for custom db file locations", () => {
    const generated = generatePagesDbModule("abc123", 3);
    expect(generated).toContain(
      "module Pages.Db exposing (Connection, default, open, get, update, transaction, testConfig)"
    );
    expect(generated).toContain("type Connection");
    expect(generated).toContain("open : String -> Connection");
    expect(generated).toContain("default : Connection");
    expect(generated).toContain("get : Connection -> BackendTask FatalError Db.Db");
    expect(generated).toContain(
      "update : Connection -> (Db.Db -> Db.Db) -> BackendTask FatalError ()"
    );
    expect(generated).toContain('( "x-schema-hash", schemaHash )');
    expect(generated).toContain("Pages.Internal.DbRequest.readMeta");
    expect(generated).toContain("Pages.Internal.DbRequest.migrateWrite");
    expect(generated).toContain("Pages.Internal.DbRequest.lockAcquire");
    expect(generated).toContain("import Pages.Internal.DbRequest");
    expect(generated).not.toContain("import BackendTask.Internal.Request");
    expect(generated).toContain(
      "connectionFields : Connection -> List ( String, Encode.Value )"
    );
    expect(generated).not.toContain("getAt :");
    expect(generated).not.toContain("updateAt :");
    expect(generated).not.toContain("transactionAt :");
    expect(generated).toContain("migrateFromV1");
    expect(generated).toContain("migrateFromVersion connection version bytes");
  });
});

describe("Pages.DbSeed codegen", () => {
  it("uses MigrateV1.seed () for schema V1", () => {
    const generated = generatePagesDbSeedModule(1);
    expect(generated).toContain("module Pages.DbSeed exposing (seedCurrent)");
    expect(generated).toContain("seedCurrent : Db.Db");
    expect(generated).toContain("MigrateV1.seed ()");
    expect(generated).not.toContain("Db.init");
  });

  it("chains from MigrateV1.seed () for schema V3 using seed functions", () => {
    const generated = generatePagesDbSeedModule(3);
    expect(generated).toContain("import Db.Migrate.V1 as MigrateV1");
    expect(generated).toContain("import Db.Migrate.V2 as MigrateV2");
    expect(generated).toContain("import Db.Migrate.V3 as MigrateV3");
    expect(generated).toContain("MigrateV1.seed ()");
    expect(generated).toContain("|> MigrateV2.seed");
    expect(generated).toContain("|> MigrateV3.seed");
  });
});
