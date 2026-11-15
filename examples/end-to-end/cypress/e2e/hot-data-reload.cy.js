// Hot data reloading in the dev server: when a file that a page's BackendTask
// reads changes, the page gets the new data, without a page reload and without
// losing the app's state.
//
// These tests change the files many times and check each time that the page
// shows exactly the new data: nothing left over from before, nothing twice.

const notesDir = "hot-data/notes";
const archiveDir = "hot-data/archive";
const frozenFile = "hot-data/frozen.txt";
const routeFile = "app/Route/HotData.elm";

const originalNotes = { a: "First note", b: "Second note" };
const originalFrozenLines = ["Frozen line one", "Frozen line two"];

function writeNote(name, body) {
  cy.writeFile(`${notesDir}/${name}.txt`, body + "\n");
}

function deleteNote(name) {
  cy.task("deleteFile", `${notesDir}/${name}.txt`);
}

function writeFrozenLines(lines) {
  cy.writeFile(frozenFile, lines.join("\n") + "\n");
}

function texts($items) {
  return [...$items].map((item) => item.textContent);
}

/**
 * The whole page must be exactly what these notes and frozen lines render
 * to. A leftover or repeated item anywhere on the page fails this.
 *
 * @param {Record<string, string>} notes
 * @param {string[]} frozenLines
 * @param {number} [count] - what the page's counter (the app's state) shows
 * @param {string} [counterLabel]
 */
function pageShowsExactly(notes, frozenLines, count = 0, counterLabel = "Count") {
  const noteItems = Object.keys(notes)
    .sort()
    .map((name) => `${name}: ${notes[name]}`);
  cy.get("body").should(($body) => {
    expect(texts($body.find("#notes li")), "notes").to.deep.equal(noteItems);
    expect(texts($body.find("#frozen li")), "frozen lines").to.deep.equal(
      frozenLines
    );
    expect($body.find("h1").length, "number of headings").to.equal(1);
    expect($body.find("#notes").length, "number of note lists").to.equal(1);
    expect($body.find("#frozen").length, "number of frozen lists").to.equal(1);
    expect($body.find("li").length, "number of list items").to.equal(
      noteItems.length + frozenLines.length
    );
    expect($body.find("#count").text()).to.equal(`${counterLabel}: ${count}`);
  });
}

function markThePage() {
  cy.window().then((win) => {
    win.stillTheSamePage = true;
  });
}

function pageWasNotReloaded() {
  cy.window().its("stillTheSamePage").should("equal", true);
  cy.get("@consoleError").should("not.have.been.called");
}

function restoreFiles() {
  cy.task("deleteFilesIn", notesDir);
  for (const [name, body] of Object.entries(originalNotes)) {
    writeNote(name, body);
  }
  writeFrozenLines(originalFrozenLines);
  cy.task("deleteFilesIn", archiveDir);
  cy.writeFile(`${archiveDir}/old.txt`, "Archived\n");
}

context("dev server hot data reloading", () => {
  let originalRouteSource = "";

  before(() => {
    cy.readFile(routeFile).then((source) => {
      originalRouteSource = source;
    });
  });

  beforeEach(() => {
    restoreFiles();
    cy.visit("/hot-data", {
      onBeforeLoad(win) {
        cy.spy(win.console, "error").as("consoleError");
      },
    });
    pageShowsExactly(originalNotes, originalFrozenLines);
    markThePage();
  });

  afterEach(() => {
    // Put the route back even if a test failed halfway, and wait for the dev
    // server to compile it, so the next test starts from a quiet server.
    cy.readFile(routeFile).then((source) => {
      if (source !== originalRouteSource) {
        cy.writeFile(routeFile, originalRouteSource);
        cy.contains("#count", "Count: ");
      }
    });
  });

  after(() => {
    restoreFiles();
  });

  it("shows each new value when a file is edited many times", () => {
    for (let i = 1; i <= 25; i++) {
      writeNote("a", `Edit number ${i}`);
      pageShowsExactly(
        { ...originalNotes, a: `Edit number ${i}` },
        originalFrozenLines
      );
    }
    pageWasNotReloaded();
  });

  it("keeps the app's state while the data changes", () => {
    cy.contains("button", "+").click();
    cy.contains("button", "+").click();
    for (let i = 1; i <= 5; i++) {
      writeNote("b", `State check ${i}`);
      pageShowsExactly(
        { ...originalNotes, b: `State check ${i}` },
        originalFrozenLines,
        2
      );
    }
    cy.contains("button", "+").click();
    pageShowsExactly(
      { ...originalNotes, b: "State check 5" },
      originalFrozenLines,
      3
    );
    pageWasNotReloaded();
  });

  it("follows files being added and removed", () => {
    const notes = { ...originalNotes };
    for (const name of ["c", "d", "e", "f", "g"]) {
      notes[name] = `Added ${name}`;
      writeNote(name, notes[name]);
      pageShowsExactly(notes, originalFrozenLines);
    }
    for (const name of ["d", "a", "g", "c"]) {
      delete notes[name];
      deleteNote(name);
      pageShowsExactly(notes, originalFrozenLines);
    }
    // And the same names again, to catch anything remembered from before.
    for (const name of ["a", "c"]) {
      notes[name] = `Back again ${name}`;
      writeNote(name, notes[name]);
      pageShowsExactly(notes, originalFrozenLines);
    }
    pageWasNotReloaded();
  });

  // The page lists this directory with a glob that runs inside it
  // (`BackendTask.inDir`), so the pattern is not relative to the project.
  it("follows files being added and removed for a glob run in another directory", () => {
    cy.contains("#archive", /^Archive: old$/);
    cy.writeFile(`${archiveDir}/newer.txt`, "Archived\n");
    cy.contains("#archive", /^Archive: newer, old$/);
    cy.writeFile(`${archiveDir}/newest.txt`, "Archived\n");
    cy.contains("#archive", /^Archive: newer, newest, old$/);
    cy.task("deleteFile", `${archiveDir}/newer.txt`);
    cy.contains("#archive", /^Archive: newest, old$/);
    pageShowsExactly(originalNotes, originalFrozenLines);
    pageWasNotReloaded();
  });

  it("shows new data inside a frozen view, as it grows and shrinks", () => {
    const versions = [
      ["One"],
      ["One", "Two", "Three"],
      ["One", "Two", "Three", "Four", "Five", "Six"],
      ["Six", "Five"],
      ["Only"],
      ["A", "B", "C", "D"],
      ["A", "B"],
    ];
    for (let round = 1; round <= 3; round++) {
      for (const lines of versions) {
        const frozenLines = lines.map((line) => `${line} (round ${round})`);
        writeFrozenLines(frozenLines);
        pageShowsExactly(originalNotes, frozenLines);
      }
    }
    pageWasNotReloaded();
  });

  it("ends up with the last value after a burst of edits", () => {
    for (let round = 1; round <= 5; round++) {
      for (let i = 1; i <= 10; i++) {
        // No waiting for the page in between.
        writeNote("a", `Burst ${round}.${i}`);
        writeFrozenLines([`Frozen burst ${round}.${i}`]);
      }
      pageShowsExactly(
        { ...originalNotes, a: `Burst ${round}.10` },
        [`Frozen burst ${round}.10`]
      );
    }
    pageWasNotReloaded();
  });

  // Tools like formatters, scripts and git change many files at once. The
  // page should fetch its data once for that, not once per file.
  it("reloads the data once when several files change at the same time", () => {
    // Let the changes from setting up the files for this test pass first.
    cy.wait(500);
    cy.intercept("GET", "/hot-data/content.dat").as("dataRequest");
    cy.task("writeFiles", {
      [`${notesDir}/a.txt`]: "All at once a\n",
      [`${notesDir}/b.txt`]: "All at once b\n",
      [`${notesDir}/c.txt`]: "All at once c\n",
      [`${notesDir}/d.txt`]: "All at once d\n",
      [`${archiveDir}/newer.txt`]: "Archived\n",
      [frozenFile]: "All at once frozen\n",
    });
    pageShowsExactly(
      {
        a: "All at once a",
        b: "All at once b",
        c: "All at once c",
        d: "All at once d",
      },
      ["All at once frozen"]
    );
    cy.contains("#archive", /^Archive: newer, old$/);
    // Give any extra requests time to show up.
    cy.wait(500);
    cy.get("@dataRequest.all").should("have.length", 1);
    pageWasNotReloaded();
  });

  it("shows the new data after coming back to the page", () => {
    writeNote("a", "Before leaving");
    pageShowsExactly({ ...originalNotes, a: "Before leaving" }, originalFrozenLines);

    cy.window().then((win) => {
      // A client-side navigation, the way a link click does it.
      win.history.pushState({}, "", "/counter");
      win.dispatchEvent(new PopStateEvent("popstate"));
    });
    cy.contains("h1", "Counter");
    // Edit while the page that reads the file is not showing.
    writeNote("a", "Edited while away");
    writeFrozenLines(["Frozen while away"]);
    cy.contains("h1", "Counter");
    cy.window().then((win) => win.history.back());

    pageShowsExactly({ ...originalNotes, a: "Edited while away" }, ["Frozen while away"]);
    writeNote("a", "After coming back");
    writeFrozenLines(["Frozen after coming back", "And a second line"]);
    pageShowsExactly({ ...originalNotes, a: "After coming back" }, [
      "Frozen after coming back",
      "And a second line",
    ]);
  });

  it("takes code changes and data changes one after another", () => {
    cy.contains("button", "+").click();
    const labels = ["Total", "Sum", "Clicks"];
    labels.forEach((label, index) => {
      const round = index + 1;
      cy.then(() => {
        cy.writeFile(
          routeFile,
          originalRouteSource.replace('"Count: "', `"${label}: "`)
        );
      });
      writeNote("a", `With code change ${round}`);
      writeFrozenLines([`Frozen with code change ${round}`]);
      pageShowsExactly(
        { ...originalNotes, a: `With code change ${round}` },
        [`Frozen with code change ${round}`],
        round,
        label
      );
      cy.contains("button", "+").click();

      writeNote("a", `After code change ${round}`);
      pageShowsExactly(
        { ...originalNotes, a: `After code change ${round}` },
        [`Frozen with code change ${round}`],
        round + 1,
        label
      );
    });
    pageWasNotReloaded();
  });
});
