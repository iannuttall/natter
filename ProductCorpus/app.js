const storageKey = "dictation-product-corpus-v2";
const allScenarios = await fetch("scenarios.json", { cache: "no-store" }).then((response) => response.json());
const presets = await fetch("presets.json", { cache: "no-store" }).then((response) => response.json());
const routePreset = window.location.pathname.split("/").filter(Boolean).at(-1);
const waitsForWritingModel = routePreset === "writing";
const requestedScenarioIds = presets[routePreset] || new URLSearchParams(window.location.search)
  .get("only")
  ?.split(",")
  .map((value) => value.trim())
  .filter(Boolean) || [];
const requestedScenarioSet = new Set(requestedScenarioIds);
const selectedScenarios = requestedScenarioIds.length
  ? allScenarios.filter((item) => requestedScenarioSet.has(item.id))
  : allScenarios;
const scenarios = selectedScenarios.length ? selectedScenarios : allScenarios;
const elements = Object.fromEntries(
  [...document.querySelectorAll("[id]")].map((element) => [element.id, element]),
);

let currentIndex = 0;
let results = {};
let runId = null;
let runStartedAt = null;
let phase = "idle";
let armedAt = null;
let lastInputAt = null;
let eventLog = [];
let hotkeyCandidate = null;
let hotkeyFirstTapAt = 0;
let settlingTask = null;
let attempt = 1;
let attemptOutputs = [];
let initialMode = null;

if (waitsForWritingModel) {
  document.title = "Dictation Formatting and Writing Run";
  elements.eyebrow.textContent = "Formatting + writing checkout";
  elements.pageTitle.textContent = "Speak it. We’ll handle the rest.";
  elements.pageDescription.textContent = "Ten short tests cover Fast, Refine and Rewrite processing. The runner waits automatically if the Rewrite model is still downloading.";
}

function scenario() {
  return scenarios[currentIndex];
}

function makeRunId() {
  return `run-${new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 17)}`;
}

function runnerInstruction(item) {
  if (item.spokenUntil) return "Read only the displayed sentence, then tap once to stop.";
  if (item.expectRecovery) return "Keep reading normally; the runner will change focus automatically.";
  if (item.expectEmpty) return "Read the command exactly; no text should appear in the destination.";
  return "Read the script exactly, then tap once to stop.";
}

function logEvent(type, detail = {}) {
  if (armedAt === null) return;
  eventLog.push({
    elapsedMs: Math.round(performance.now() - armedAt),
    attempt,
    type,
    ...detail,
  });
  const count = eventLog.filter((event) => event.type === "input").length;
  elements.eventCount.textContent = `${count} input event${count === 1 ? "" : "s"}`;
}

function renderScenario() {
  const item = scenario();
  elements.position.textContent = `${String(currentIndex + 1).padStart(2, "0")} / ${scenarios.length}`;
  elements.category.textContent = item.category;
  elements.mode.textContent = item.mode;
  elements.title.textContent = item.title;
  elements.instruction.textContent = runnerInstruction(item);
  elements.script.textContent = item.spokenUntil || item.script;
  elements.spokenUntil.hidden = !item.spokenUntil;
  elements.spokenUntil.textContent = item.spokenUntil ? "Stop at the end of the displayed sentence." : "";
  elements.primaryTarget.value = "";
  elements.secondaryTarget.value = "";
  delete elements.secondaryTarget.dataset.recovery;
  elements.secondaryTarget.hidden = true;
  elements.resultPanel.hidden = true;
  elements.retryButton.hidden = true;
  elements.retryButton.textContent = "Retry this test";
  elements.eventCount.textContent = "0 events";
  elements.saveState.textContent = runId ? "Syncing mode…" : "Not started";
  updateProgress();
}

function updateProgress() {
  const completed = Object.keys(results).length;
  const passing = Object.values(results).filter((result) => result.passed).length;
  elements.completedCount.textContent = `${completed} / ${scenarios.length}`;
  elements.passCount.textContent = completed ? `${passing} passing · ${completed - passing} need review` : "Waiting to start";
  elements.progressBar.style.width = `${(completed / scenarios.length) * 100}%`;
}

async function startRun() {
  if (phase !== "idle" && phase !== "paused" && phase !== "complete") return;
  if (phase === "paused") {
    phase = "switching";
    elements.startButton.hidden = true;
    elements.pauseButton.hidden = false;
    return prepareCurrentScenario();
  }
  if (phase === "complete") {
    currentIndex = 0;
    results = {};
  }
  try {
    const status = await fetch("/api/status", { cache: "no-store" })
      .then((response) => response.json());
    initialMode = status.selectedMode || null;
  } catch {
    initialMode = null;
  }
  runId = makeRunId();
  runStartedAt = new Date().toISOString();
  phase = "switching";
  elements.startButton.hidden = true;
  elements.pauseButton.hidden = false;
  await prepareCurrentScenario();
}

async function prepareCurrentScenario() {
  clearTimeout(settlingTask);
  phase = "switching";
  attempt = 1;
  attemptOutputs = [];
  renderScenario();

  if (["Email", "Article"].includes(scenario().mode) && !(await writingModelInstalled())) {
    if (waitsForWritingModel) return waitForWritingModel();
    return skipMissingWritingModel();
  }

  try {
    const response = await fetch("/api/mode", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode: scenario().mode }),
    });
    if (!response.ok) throw new Error(`mode switch returned ${response.status}`);
    elements.saveState.textContent = `${scenario().mode} selected`;
  } catch (error) {
    elements.saveState.textContent = "Mode sync failed";
    elements.runState.textContent = `Could not select ${scenario().mode}: ${error.message}`;
    phase = "paused";
    elements.startButton.hidden = false;
    elements.startButton.textContent = "Resume";
    return;
  }

  await new Promise((resolve) => window.setTimeout(resolve, 350));
  armScenario();
}

async function writingModelInstalled() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) return false;
    const status = await response.json();
    return Boolean(status.writingInstalled);
  } catch {
    return false;
  }
}

function waitForWritingModel() {
  phase = "waiting-model";
  elements.runState.textContent = "Waiting for the Rewrite model download to finish…";
  elements.saveState.textContent = "Checking model…";
  settlingTask = window.setTimeout(async () => {
    if (phase !== "waiting-model") return;
    if (await writingModelInstalled()) {
      elements.runState.textContent = "Rewrite model ready · continuing automatically…";
      return prepareCurrentScenario();
    }
    waitForWritingModel();
  }, 2_000);
}

function skipMissingWritingModel() {
  const item = scenario();
  const result = {
    scenarioId: item.id,
    mode: item.mode,
    completedAt: new Date().toISOString(),
    passed: false,
    skipped: true,
    skipReason: "Writing tools model is not installed",
    output: "",
    attempts: [],
    checks: [{ label: "Writing tools model is installed", passed: false }],
    events: [],
  };
  results[item.id] = result;
  showResult(result);
  elements.runState.textContent = "Skipped · install Writing tools in Dictation Settings to test this mode";
  saveResults().finally(() => {
    if (currentIndex === scenarios.length - 1) {
      finishRun();
      return;
    }
    settlingTask = window.setTimeout(() => {
      currentIndex += 1;
      prepareCurrentScenario();
    }, 1_600);
  });
}

function armScenario() {
  phase = "armed";
  armedAt = performance.now();
  lastInputAt = null;
  eventLog = attempt === 1 ? [] : eventLog;
  hotkeyCandidate = null;
  hotkeyFirstTapAt = 0;
  elements.primaryTarget.value = "";
  elements.secondaryTarget.value = "";
  delete elements.secondaryTarget.dataset.recovery;
  elements.secondaryTarget.hidden = true;
  logEvent("armed", { mode: scenario().mode });
  elements.runState.textContent = attempt > 1
    ? `Ready for repeat ${attempt} · double tap Right Option`
    : "Ready · double tap Right Option and read the script";
  elements.primaryTarget.focus();
}

function handleModifierPress(event) {
  if (!runId || event.repeat || !["AltRight", "ControlRight"].includes(event.code)) return;
  const now = performance.now();
  logEvent("hotkey", { code: event.code, phase });

  if (phase === "armed") {
    if (hotkeyCandidate === event.code && now - hotkeyFirstTapAt <= 650) {
      phase = "recording";
      hotkeyCandidate = null;
      elements.runState.textContent = "Recording · read the full script, then tap once to stop";
      elements.saveState.textContent = "Recording";
    } else {
      hotkeyCandidate = event.code;
      hotkeyFirstTapAt = now;
      elements.runState.textContent = "First tap detected…";
    }
    return;
  }

  if (phase === "recording") {
    phase = "settling";
    elements.runState.textContent = "Stopped · waiting for the final local result…";
    elements.saveState.textContent = "Evaluating…";
    waitForSettledResult();
  }
}

async function waitForSettledResult() {
  const started = performance.now();
  const maximumWait = ["Email", "Article"].includes(scenario().mode) ? 90_000 : 20_000;

  while (phase === "settling" && performance.now() - started < maximumWait) {
    if (scenario().expectRecovery && performance.now() - started > 700) {
      await readRecoveryClipboard();
    }

    const output = scenario().expectRecovery
      ? elements.secondaryTarget.dataset.recovery || ""
      : elements.primaryTarget.value;
    const quietFor = lastInputAt === null ? Infinity : performance.now() - lastInputAt;
    const minimumWait = scenario().expectEmpty ? 1_800 : 650;
    const hasSettledOutput = output.trim().length > 0 && quietFor > 900;
    const emptyCommandSettled = scenario().expectEmpty && performance.now() - started > 2_200;

    if (performance.now() - started > minimumWait && (hasSettledOutput || emptyCommandSettled)) {
      return completeAttempt();
    }
    await new Promise((resolve) => window.setTimeout(resolve, 180));
  }
  completeAttempt({ timedOut: true });
}

async function readRecoveryClipboard() {
  try {
    const response = await fetch("/api/clipboard", { cache: "no-store" });
    const payload = await response.json();
    elements.secondaryTarget.dataset.recovery = payload.text || "";
  } catch {
    elements.secondaryTarget.dataset.recovery = "";
  }
}

function completeAttempt({ timedOut = false } = {}) {
  const item = scenario();
  const output = item.expectRecovery
    ? elements.secondaryTarget.dataset.recovery || ""
    : elements.primaryTarget.value.trim();
  attemptOutputs.push(output);

  const repetitions = item.repeatCount || 1;
  if (attempt < repetitions) {
    logEvent("attempt-complete", { outputLength: output.length });
    attempt += 1;
    elements.runState.textContent = `First run captured · preparing repeat ${attempt}`;
    settlingTask = window.setTimeout(armScenario, 700);
    return;
  }

  const checks = evaluateChecks(item, output, timedOut);
  const passed = checks.every((check) => check.passed);
  const result = {
    scenarioId: item.id,
    mode: item.mode,
    completedAt: new Date().toISOString(),
    passed,
    timedOut,
    output,
    attempts: attemptOutputs,
    checks,
    events: eventLog,
  };
  results[item.id] = result;
  localStorage.setItem(storageKey, JSON.stringify({ runId, currentIndex, results }));
  phase = "saving";
  showResult(result);
  saveResults().finally(() => {
    if (currentIndex === scenarios.length - 1) {
      finishRun();
      return;
    }
    settlingTask = window.setTimeout(() => {
      currentIndex += 1;
      prepareCurrentScenario();
    }, 1_600);
  });
}

function evaluateChecks(item, output, timedOut) {
  const lowered = output.toLocaleLowerCase();
  const checks = [];
  if (timedOut) checks.push({ label: "Final result arrived before timeout", passed: false });
  if (item.expectEmpty) checks.push({ label: "Destination stayed empty", passed: output.length === 0 });
  for (const value of item.required || []) {
    checks.push({ label: `Contains “${value}”`, passed: lowered.includes(value.toLocaleLowerCase()) });
  }
  for (const value of item.forbidden || []) {
    checks.push({ label: `Omits “${value}”`, passed: !lowered.includes(value.toLocaleLowerCase()) });
  }
  for (const alternatives of item.requiredAny || []) {
    checks.push({
      label: `Contains ${alternatives.map((value) => `“${value}”`).join(" or ")}`,
      passed: alternatives.some((value) => lowered.includes(value.toLocaleLowerCase())),
    });
  }
  if (item.capitalizedInitial) {
    checks.push({ label: "Starts with a capital letter", passed: /^\s*[A-Z]/.test(output) });
  }
  if (item.forbidHeading) {
    checks.push({
      label: "Adds no heading to a short passage",
      passed: !/^\s*#{1,6}\s/m.test(output),
    });
  }
  if (item.terminalPunctuation) {
    checks.push({ label: "Ends with sentence punctuation", passed: /[.!?]["')\]]?$/.test(output) });
  }
  if (item.minInputEvents > 0) {
    const inputEvents = eventLog.filter((event) => event.type === "input" && event.target === "primary").length;
    checks.push({ label: `${item.minInputEvents}+ input events`, passed: inputEvents >= item.minInputEvents });
  }
  if (item.expectRecovery) {
    checks.push({ label: "Complete transcript recovered from clipboard", passed: output.length > 0 });
  }
  if ((item.repeatCount || 1) > 1) {
    checks.push({ label: "Both consecutive sessions produced output", passed: attemptOutputs.every(Boolean) });
  }
  return checks;
}

function showResult(result) {
  elements.resultPanel.hidden = false;
  elements.resultPanel.className = `result-panel ${result.passed ? "pass" : "fail"}`;
  elements.resultTitle.textContent = result.skipped ? "Skipped" : result.passed ? "Passed" : "Needs review";
  elements.resultSummary.textContent = result.skipped
    ? "The optional Writing tools model is not installed; continuing…"
    : result.passed
      ? "Advancing automatically…"
      : "Saved with the failed checks; continuing…";
  elements.automaticChecks.replaceChildren();
  for (const check of result.checks) {
    const chip = document.createElement("span");
    chip.className = `check ${check.passed ? "pass" : "fail"}`;
    chip.textContent = `${check.passed ? "✓" : "×"} ${check.label}`;
    elements.automaticChecks.append(chip);
  }
  elements.retryButton.hidden = false;
  updateProgress();
}

async function saveResults() {
  const payload = {
    version: 2,
    runId,
    startedAt: runStartedAt,
    updatedAt: new Date().toISOString(),
    app: "Natter",
    completed: Object.keys(results).length,
    total: scenarios.length,
    results,
  };
  try {
    const response = await fetch("/api/results", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const saved = await response.json();
    if (!response.ok) throw new Error(saved.error || `save returned ${response.status}`);
    elements.resultsPath.textContent = `Saved to ${saved.path}`;
    elements.saveState.textContent = "Saved locally";
  } catch (error) {
    elements.resultsPath.textContent = `Save failed: ${error.message}`;
    elements.saveState.textContent = "Save failed";
  }
}

function handleInput(target, event) {
  lastInputAt = performance.now();
  logEvent("input", {
    target,
    inputType: event.inputType,
    data: event.data,
    valueLength: event.currentTarget.value.length,
  });

  const item = scenario();
  if (target === "primary" && item.expectRecovery && !elements.secondaryTarget.hidden) return;
  if (target === "primary" && item.expectRecovery) {
    const count = eventLog.filter((logged) => logged.type === "input" && logged.target === "primary").length;
    if (count >= (item.focusAfterInputEvents || 2)) {
      elements.secondaryTarget.hidden = false;
      elements.secondaryTarget.focus();
      logEvent("automatic-focus-change", { target: "secondary" });
    }
  }
}

function pauseRun() {
  clearTimeout(settlingTask);
  phase = "paused";
  elements.runState.textContent = "Paused";
  elements.startButton.hidden = false;
  elements.startButton.textContent = "Resume";
  elements.pauseButton.hidden = true;
  restoreInitialMode();
}

function retryScenario() {
  clearTimeout(settlingTask);
  if (phase === "complete") {
    const failedIds = Object.values(results)
      .filter((result) => !result.passed && !result.skipped)
      .map((result) => result.scenarioId);
    if (failedIds.length) {
      window.location.assign(`/?only=${encodeURIComponent(failedIds.join(","))}`);
    }
    return;
  }
  delete results[scenario().id];
  prepareCurrentScenario();
}

async function restoreInitialMode() {
  if (!initialMode) return;
  try {
    await fetch("/api/mode", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode: initialMode }),
    });
  } catch {
    // The completed run remains valid if the native app has quit.
  }
}

async function finishRun() {
  phase = "restoring";
  elements.runState.textContent = "Run complete · restoring your previous mode…";
  await restoreInitialMode();
  phase = "complete";
  elements.runState.textContent = "Run complete · every result is saved locally";
  elements.saveState.textContent = initialMode
    ? `${initialMode[0].toUpperCase()}${initialMode.slice(1)} restored`
    : "Complete";
  elements.startButton.hidden = false;
  elements.startButton.textContent = "Start another run";
  elements.pauseButton.hidden = true;

  const failedCount = Object.values(results).filter(
    (result) => !result.passed && !result.skipped,
  ).length;
  elements.retryButton.hidden = failedCount === 0;
  elements.retryButton.textContent = failedCount === 1
    ? "Retry failed test"
    : `Retry ${failedCount} failed tests`;
}

document.addEventListener("keydown", handleModifierPress, { capture: true });
elements.primaryTarget.addEventListener("input", (event) => handleInput("primary", event));
elements.secondaryTarget.addEventListener("input", (event) => handleInput("secondary", event));
for (const [name, field] of [["primary", elements.primaryTarget], ["secondary", elements.secondaryTarget]]) {
  field.addEventListener("focus", () => logEvent("focus", { target: name }));
  field.addEventListener("blur", () => logEvent("blur", { target: name }));
}
elements.startButton.addEventListener("click", startRun);
elements.pauseButton.addEventListener("click", pauseRun);
elements.retryButton.addEventListener("click", retryScenario);

renderScenario();
