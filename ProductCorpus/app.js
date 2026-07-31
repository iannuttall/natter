const storageKey = "dictation-product-corpus-v1";
const scenarios = await fetch("scenarios.json").then((response) => response.json());
const categories = [...new Set(scenarios.map((scenario) => scenario.category))];

const elements = Object.fromEntries(
  [...document.querySelectorAll("[id]")].map((element) => [element.id, element]),
);
let currentIndex = Math.min(Number(localStorage.getItem(`${storageKey}-current`) || 0), scenarios.length - 1);
let results = JSON.parse(localStorage.getItem(storageKey) || "{}");
let armedAt = null;
let eventLog = [];

function currentScenario() {
  return scenarios[currentIndex];
}

function saveResults() {
  localStorage.setItem(storageKey, JSON.stringify(results));
  localStorage.setItem(`${storageKey}-current`, String(currentIndex));
}

function logEvent(type, detail = {}) {
  if (armedAt === null) return;
  eventLog.push({
    elapsedMs: Math.round(performance.now() - armedAt),
    type,
    ...detail,
  });
  elements.runState.textContent = `${eventLog.filter((event) => event.type === "input").length} input events captured`;
}

function render() {
  const scenario = currentScenario();
  const saved = results[scenario.id];
  elements.position.textContent = `${String(currentIndex + 1).padStart(2, "0")} / ${scenarios.length}`;
  elements.category.textContent = scenario.category;
  elements.mode.textContent = scenario.mode;
  elements.title.textContent = scenario.title;
  elements.instruction.textContent = scenario.instruction;
  elements.script.textContent = scenario.script;
  elements.spokenUntil.hidden = !scenario.spokenUntil;
  elements.spokenUntil.textContent = scenario.spokenUntil
    ? `Stop marker: ${scenario.spokenUntil}`
    : "";
  elements.savedState.textContent = saved ? (saved.passed ? "Passed" : "Needs review") : "";
  elements.savedState.className = `saved-state ${saved ? (saved.passed ? "pass" : "fail") : ""}`;
  elements.primaryTarget.value = saved?.output || "";
  elements.secondaryTarget.value = saved?.secondaryOutput || "";
  elements.recoveryTarget.value = saved?.recoveryOutput || "";
  elements.notes.value = saved?.notes || "";
  elements.recoveryPanel.hidden = !scenario.expectRecovery;
  elements.secondaryPanel.open = Boolean(scenario.expectRecovery);
  elements.runState.textContent = saved ? `${saved.events.length} events in saved run` : "Not armed";
  armedAt = null;
  eventLog = [];
  renderCategories();
  renderChecks(saved?.checks || []);
  renderManualChecks(saved?.manual || {});
  renderProgress();
  elements.previousButton.disabled = currentIndex === 0;
  elements.nextButton.disabled = currentIndex === scenarios.length - 1;
}

function renderCategories() {
  elements.categories.replaceChildren();
  for (const category of categories) {
    const categoryScenarios = scenarios.filter((scenario) => scenario.category === category);
    const done = categoryScenarios.filter((scenario) => results[scenario.id]).length;
    const button = document.createElement("button");
    button.className = currentScenario().category === category ? "category active" : "category";
    const label = document.createElement("span");
    label.textContent = category;
    const count = document.createElement("small");
    count.textContent = `${done}/${categoryScenarios.length}`;
    button.append(label, count);
    button.addEventListener("click", () => {
      currentIndex = scenarios.findIndex((scenario) => scenario.category === category);
      saveResults();
      render();
    });
    elements.categories.append(button);
  }
}

function renderProgress() {
  const completed = Object.keys(results).length;
  const passing = Object.values(results).filter((result) => result.passed).length;
  elements.completedCount.textContent = `${completed} complete`;
  elements.passCount.textContent = `${passing} passing`;
  elements.progressBar.style.width = `${(completed / scenarios.length) * 100}%`;
}

function renderChecks(checks) {
  elements.automaticChecks.replaceChildren();
  const scenario = currentScenario();
  const definitions = checks.length ? checks : automaticCheckDefinitions(scenario).map((label) => ({ label }));
  for (const check of definitions) {
    const row = document.createElement("div");
    row.className = `check-row ${check.passed === true ? "pass" : check.passed === false ? "fail" : ""}`;
    row.textContent = check.passed === true ? `✓ ${check.label}` : check.passed === false ? `× ${check.label}` : `· ${check.label}`;
    elements.automaticChecks.append(row);
  }
}

function renderManualChecks(savedManual) {
  elements.manualChecks.replaceChildren();
  const checks = currentScenario().manualChecks || [];
  if (!checks.length) {
    const row = document.createElement("div");
    row.className = "check-row quiet";
    row.textContent = "No manual check for this scenario";
    elements.manualChecks.append(row);
    return;
  }
  checks.forEach((label, index) => {
    const wrapper = document.createElement("label");
    wrapper.className = "manual-row";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = Boolean(savedManual[index]);
    input.dataset.index = String(index);
    const text = document.createElement("span");
    text.textContent = label;
    wrapper.append(input, text);
    elements.manualChecks.append(wrapper);
  });
}

function automaticCheckDefinitions(scenario) {
  const labels = [];
  if (scenario.expectEmpty) labels.push("Destination stayed empty");
  for (const value of scenario.required || []) labels.push(`Contains “${value}”`);
  for (const value of scenario.forbidden || []) labels.push(`Does not contain “${value}”`);
  if (scenario.minInputEvents > 0) labels.push(`At least ${scenario.minInputEvents} separate input events`);
  if (scenario.expectRecovery) labels.push("Recovery clipboard contains the complete transcript");
  return labels;
}

function evaluate() {
  const scenario = currentScenario();
  const output = elements.primaryTarget.value.trim();
  const recoveryOutput = elements.recoveryTarget.value.trim();
  const evaluatedText = scenario.expectRecovery ? recoveryOutput : output;
  const lowered = evaluatedText.toLocaleLowerCase();
  const checks = [];

  if (scenario.expectEmpty) {
    checks.push({ label: "Destination stayed empty", passed: output.length === 0 });
  }
  for (const value of scenario.required || []) {
    checks.push({
      label: `Contains “${value}”`,
      passed: lowered.includes(value.toLocaleLowerCase()),
    });
  }
  for (const value of scenario.forbidden || []) {
    checks.push({
      label: `Does not contain “${value}”`,
      passed: !lowered.includes(value.toLocaleLowerCase()),
    });
  }
  if (scenario.minInputEvents > 0) {
    const inputEvents = eventLog.filter((event) => event.type === "input" && event.target === "primary").length;
    checks.push({
      label: `At least ${scenario.minInputEvents} separate input events`,
      passed: inputEvents >= scenario.minInputEvents,
    });
  }
  if (scenario.expectRecovery) {
    checks.push({
      label: "Recovery clipboard contains the complete transcript",
      passed: recoveryOutput.length > 0 && (scenario.required || []).every(
        (value) => recoveryOutput.toLocaleLowerCase().includes(value.toLocaleLowerCase()),
      ),
    });
  }

  const manual = Object.fromEntries(
    [...elements.manualChecks.querySelectorAll("input")].map((input) => [input.dataset.index, input.checked]),
  );
  const manualPassed = [...elements.manualChecks.querySelectorAll("input")].every((input) => input.checked);
  const passed = checks.every((check) => check.passed) && manualPassed;
  results[scenario.id] = {
    scenarioId: scenario.id,
    mode: scenario.mode,
    completedAt: new Date().toISOString(),
    passed,
    output,
    secondaryOutput: elements.secondaryTarget.value,
    recoveryOutput,
    notes: elements.notes.value,
    checks,
    manual,
    events: eventLog,
  };
  saveResults();
  render();
}

function arm() {
  elements.primaryTarget.value = "";
  elements.secondaryTarget.value = "";
  elements.recoveryTarget.value = "";
  armedAt = performance.now();
  eventLog = [{ elapsedMs: 0, type: "armed", mode: currentScenario().mode }];
  elements.runState.textContent = "Armed · use the native hotkey now";
  elements.primaryTarget.focus();
}

function move(direction) {
  currentIndex = Math.max(0, Math.min(scenarios.length - 1, currentIndex + direction));
  saveResults();
  render();
}

elements.primaryTarget.addEventListener("input", (event) => logEvent("input", {
  target: "primary",
  inputType: event.inputType,
  data: event.data,
  valueLength: elements.primaryTarget.value.length,
}));
elements.secondaryTarget.addEventListener("input", (event) => logEvent("input", {
  target: "secondary",
  inputType: event.inputType,
  data: event.data,
  valueLength: elements.secondaryTarget.value.length,
}));
for (const [name, element] of [["primary", elements.primaryTarget], ["secondary", elements.secondaryTarget]]) {
  element.addEventListener("focus", () => logEvent("focus", { target: name }));
  element.addEventListener("blur", () => logEvent("blur", { target: name }));
}
document.addEventListener("visibilitychange", () => logEvent("visibility", { state: document.visibilityState }));
elements.armButton.addEventListener("click", arm);
elements.evaluateButton.addEventListener("click", evaluate);
elements.previousButton.addEventListener("click", () => move(-1));
elements.nextButton.addEventListener("click", () => move(1));
elements.skipButton.addEventListener("click", () => move(1));
elements.readClipboardButton.addEventListener("click", async () => {
  try {
    elements.recoveryTarget.value = await navigator.clipboard.readText();
    logEvent("clipboard-read", { valueLength: elements.recoveryTarget.value.length });
  } catch (error) {
    elements.runState.textContent = `Clipboard read failed: ${error.message}`;
  }
});
elements.exportButton.addEventListener("click", () => {
  const payload = {
    version: 1,
    createdAt: new Date().toISOString(),
    app: "Dictation",
    scenarios,
    results,
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `dictation-product-corpus-${new Date().toISOString().slice(0, 10)}.json`;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
});
elements.clearButton.addEventListener("click", () => {
  if (!window.confirm("Delete all locally saved product test results?")) return;
  results = {};
  currentIndex = 0;
  saveResults();
  render();
});

render();
