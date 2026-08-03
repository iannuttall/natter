import fs from "node:fs";

const path = process.argv[2];
if (!path) {
  console.error("Usage: node scripts/check-agent-self-edit-evals.mjs <results.json>");
  process.exit(2);
}

const summary = JSON.parse(fs.readFileSync(path, "utf8"));
const results = summary.results ?? [];
const positive = results.filter((result) =>
  !result.id.startsWith("negative-") && !result.id.startsWith("bypass-")
);
const negative = results.filter((result) => result.id.startsWith("negative-"));
const bypass = results.filter((result) => result.id.startsWith("bypass-"));
const exact = (result) => result.expectedWordErrorRate === 0;
const percentile = (values, fraction) => {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.round((sorted.length - 1) * fraction)];
};
const rate = (items, predicate) =>
  items.length === 0 ? 1 : items.filter(predicate).length / items.length;

const positiveExact = rate(positive, exact);
const negativeExact = rate(negative, exact);
const bypassExact = rate(bypass, exact);
const bypassed = rate(bypass, (result) => result.pipelineOutcome === "bypassed");
const bypassP95Ms = percentile(bypass.map((result) => result.latencySeconds), 0.95) * 1_000;
const correctionP95Seconds = percentile(
  positive.map((result) => result.latencySeconds),
  0.95
);
const correctionBudgetSeconds = Number(process.env.NATTER_SELF_EDIT_P95_BUDGET_SECONDS ?? "4");

console.log(`Positive exact: ${(positiveExact * 100).toFixed(1)}% (${positive.filter(exact).length}/${positive.length})`);
console.log(`Negative exact: ${(negativeExact * 100).toFixed(1)}% (${negative.filter(exact).length}/${negative.length})`);
console.log(`Bypass exact: ${(bypassExact * 100).toFixed(1)}% (${bypass.filter(exact).length}/${bypass.length})`);
console.log(`Bypass routed: ${(bypassed * 100).toFixed(1)}%`);
console.log(`Bypass p95: ${bypassP95Ms.toFixed(3)}ms`);
console.log(`Correction p95: ${correctionP95Seconds.toFixed(3)}s (budget ${correctionBudgetSeconds.toFixed(3)}s)`);
console.log(`Required checks: ${(summary.requiredPassRate * 100).toFixed(1)}%`);
console.log(`Forbidden checks: ${(summary.forbiddenPassRate * 100).toFixed(1)}%`);

const failures = results.filter((result) => !exact(result));
for (const failure of failures) {
  console.log(`\nFAIL ${failure.id} [${failure.pipelineOutcome}]`);
  console.log(`  expected: ${failure.expected}`);
  console.log(`  actual:   ${failure.output}`);
}

const passed = positiveExact === 1
  && negativeExact === 1
  && bypassExact === 1
  && bypassed === 1
  && bypassP95Ms <= 5
  && correctionP95Seconds <= correctionBudgetSeconds
  && summary.requiredPassRate === 1
  && summary.forbiddenPassRate === 1;

if (!passed) process.exit(1);
