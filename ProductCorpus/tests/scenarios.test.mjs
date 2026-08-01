import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const scenarios = JSON.parse(
  await readFile(new URL("../scenarios.json", import.meta.url), "utf8"),
);
const presets = JSON.parse(
  await readFile(new URL("../presets.json", import.meta.url), "utf8"),
);
const formatting = JSON.parse(
  await readFile(new URL("../formatting-fixtures.json", import.meta.url), "utf8"),
);

test("scenario ids are unique and every scenario is actionable", () => {
  assert.ok(scenarios.length >= 20);
  assert.equal(new Set(scenarios.map((scenario) => scenario.id)).size, scenarios.length);
  for (const scenario of scenarios) {
    assert.ok(scenario.category);
    assert.ok(["Raw", "Agent", "Clean", "Email", "Article"].includes(scenario.mode));
    assert.ok(scenario.title);
    assert.ok(scenario.instruction);
    assert.ok(scenario.script.length >= 40);
    assert.ok(Array.isArray(scenario.required));
    assert.ok(Array.isArray(scenario.forbidden));
    assert.ok(Array.isArray(scenario.manualChecks));
    if (scenario.requiredAny) {
      assert.ok(scenario.requiredAny.every((group) => group.length >= 2));
    }
  }
});

test("feature corpus covers every app mode and failure-sensitive workflow", () => {
  const modes = new Set(scenarios.map((scenario) => scenario.mode));
  assert.deepEqual(modes, new Set(["Raw", "Agent", "Clean", "Email", "Article"]));

  const categories = new Set(scenarios.map((scenario) => scenario.category));
  for (const required of ["Live delivery", "Agent work", "Recovery", "Corrections", "Clean mode", "Email mode", "Article mode", "Stress"]) {
    assert.ok(categories.has(required), `missing ${required}`);
  }
  assert.ok(scenarios.some((scenario) => scenario.expectRecovery));
  assert.ok(scenarios.some((scenario) => scenario.expectEmpty));
  assert.ok(scenarios.some((scenario) => scenario.spokenUntil));
  assert.ok(scenarios.filter((scenario) => scenario.terminalPunctuation).length >= 2);
});

test("named regression preset stays short and references valid scenarios", () => {
  const scenarioIds = new Set(scenarios.map((scenario) => scenario.id));

  assert.equal(presets.regression.length, 5);
  assert.ok(presets.regression.every((id) => scenarioIds.has(id)));
  assert.equal(presets.delivery.length, 2);
  assert.ok(presets.delivery.every((id) => scenarioIds.has(id)));
  assert.deepEqual(presets.repair, ["raw-protected-facts"]);
  assert.equal(presets.writing.length, 10);
  assert.ok(presets.writing.every((id) => scenarioIds.has(id)));
  assert.deepEqual(
    new Set(presets.writing.map((id) => scenarios.find((scenario) => scenario.id === id).mode)),
    new Set(["Agent", "Clean", "Email", "Article"]),
  );
});

test("formatting corpus separates deterministic grammar from smart formatting", () => {
  assert.ok(formatting.fixtures.length >= 30);
  assert.equal(
    new Set(formatting.fixtures.map((fixture) => fixture.id)).size,
    formatting.fixtures.length,
  );

  const categories = new Set(formatting.fixtures.map((fixture) => fixture.category));
  for (const category of [
    "Versions",
    "Identifiers",
    "Flags",
    "Numbers and units",
    "Dates",
    "Addresses and paths",
    "Ambiguous prose",
  ]) {
    assert.ok(categories.has(category), `missing ${category}`);
  }

  for (const fixture of formatting.fixtures) {
    assert.ok(["prose", "technical"].includes(fixture.context));
    assert.ok(fixture.spoken);
    assert.ok(fixture.deterministicExpected);
    assert.ok(Array.isArray(fixture.protected));
    assert.ok(Array.isArray(fixture.forbidden));
    assert.equal(Boolean(fixture.smartInstructions), Boolean(fixture.smartExpected));
  }
});
