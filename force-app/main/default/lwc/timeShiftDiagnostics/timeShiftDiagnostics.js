/**
 * Time Trail Setup > Diagnostics. An admin enters a Contact or Account Id and
 * the actual timeline draws, with three tabs: Config (the data sources and the
 * user's configuration and permissions), Performance (the load time in plain
 * terms: the total wait, the server's share and the browser's; and every
 * query with its time) and Output (the timeline itself). Setup's own text is
 * English.
 */
import { LightningElement } from "lwc";
import run from "@salesforce/apex/TimeShiftDiagnosticController.run";
import { recent, subscribe, clear, currentServerReport } from "c/timeShiftTraceLog";

const ID_PATTERN = /^([a-zA-Z0-9]{15}|[a-zA-Z0-9]{18})$/;
// Over this many ms a query is marked slow.
const SLOW_MS = 500;

const HISTORY = ["0.25", "0.5", "1", "2", "3", "5", "10"];
const FUTURE = ["None", "0.25", "0.5", "1", "2", "5", "10"];
const TABS = [
  { key: "config", label: "Config" },
  { key: "performance", label: "Performance" },
  { key: "output", label: "Output" }
];

const plain = (error) => error?.body?.message ?? error?.message ?? "Something went wrong.";
const seconds = (ms) => (ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`);

export default class TimeShiftDiagnostics extends LightningElement {
  recordId = "";
  layout = "Across";
  history = "0.5";
  future = "None";

  report;
  error;
  running = false;
  tab = "performance";
  // The timeline is drawn for this record, anew each run.
  drawnFor;
  lines = [];
  // What the server reported for the card's own opening request.
  perf;
  _stop;

  historyOptions = HISTORY.map((value) => ({ label: `${value} year${value === "1" ? "" : "s"}`, value }));
  futureOptions = FUTURE.map((value) => ({ label: value === "None" ? "None (up to today)" : `${value} years`, value }));
  layoutOptions = [
    { label: "Across (horizontal)", value: "Across" },
    { label: "Down (vertical)", value: "Down" }
  ];

  connectedCallback() {
    this.lines = recent();
    this.perf = currentServerReport();
    this._stop = subscribe(() => {
      this.lines = recent();
      this.perf = currentServerReport();
    });
  }

  disconnectedCallback() {
    this._stop?.();
  }

  // ---- inputs ---------------------------------------------------------------

  handleId(event) {
    this.recordId = event.target.value?.trim() ?? "";
  }
  handleLayout(event) {
    this.layout = event.detail.value;
  }
  handleHistory(event) {
    this.history = event.detail.value;
  }
  handleFuture(event) {
    this.future = event.detail.value;
  }
  handleKey(event) {
    if (event.key === "Enter") this.runLoad();
  }

  get cannotRun() {
    return !ID_PATTERN.test(this.recordId) || this.running;
  }
  get runLabel() {
    return this.running ? "Running…" : "Draw the timeline and diagnose it";
  }
  // The card is asked to report its own request, so what is shown is the
  // request the card made, not another one beside it.
  get diagnoseCard() {
    return true;
  }

  // ---- running --------------------------------------------------------------

  async runLoad() {
    if (this.cannotRun) return;
    // The card is drawn anew, so its load is timed from nothing.
    this.drawnFor = undefined;
    clear();
    await Promise.resolve();
    this.drawnFor = this.recordId;
    this.tab = "performance";
    this.running = true;
    this.error = undefined;
    try {
      this.report = await run({
        recordId: this.recordId,
        mode: "config",
        layout: this.layout,
        historyYears: this.history,
        futureYears: this.future
      });
    } catch (e) {
      this.report = undefined;
      this.error = plain(e);
    } finally {
      this.running = false;
    }
  }

  // ---- tabs -----------------------------------------------------------------

  get tabs() {
    return TABS.map((t) => ({
      ...t,
      selected: t.key === this.tab,
      ariaSelected: t.key === this.tab ? "true" : "false",
      tabindex: t.key === this.tab ? "0" : "-1",
      className: `tab${t.key === this.tab ? " tab_on" : ""}`
    }));
  }
  handleTab(event) {
    this.tab = event.currentTarget.dataset.tab;
  }
  handleTabKey(event) {
    const keys = TABS.map((t) => t.key);
    const at = keys.indexOf(this.tab);
    let next = at;
    if (event.key === "ArrowRight") next = (at + 1) % keys.length;
    else if (event.key === "ArrowLeft") next = (at - 1 + keys.length) % keys.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = keys.length - 1;
    else return;
    event.preventDefault();
    this.tab = keys[next];
    this.template.querySelector(`.tab[data-tab="${keys[next]}"]`)?.focus();
  }
  get isConfig() {
    return this.tab === "config";
  }
  get isPerformance() {
    return this.tab === "performance";
  }
  // The timeline stays on the page whichever tab is showing, so its load is
  // timed as it really is; off the Output tab it is only out of sight.
  get outputClass() {
    return `tabpanel tabpanel_output${this.tab === "output" ? "" : " tabpanel_off"}`;
  }
  get outputHidden() {
    return this.tab === "output" ? "false" : "true";
  }

  // ---- the timeline drawn ------------------------------------------------------

  get hasTimeline() {
    return Boolean(this.drawnFor);
  }
  get cardLayout() {
    return this.layout === "Down" ? "Vertical" : "Horizontal";
  }
  get hasReport() {
    return Boolean(this.report);
  }
  get outputSummary() {
    const t = this.perf;
    if (!t) return "";
    return `${t.events} item${t.events === 1 ? "" : "s"} read for the first screen, from ${t.days} day${t.days === 1 ? "" : "s"} with items${t.groupedRows ? `, ${t.groupedRows} of them grouped` : ""}.`;
  }

  // ---- Config -----------------------------------------------------------------

  get sources() {
    return (this.report?.sources ?? []).map((s) => ({
      ...s,
      key: s.developerName,
      className: `row${s.status === "ignored" ? " row_muted" : ""}`,
      statusText: s.status === "used" ? "Used" : "Ignored",
      statusClass: `badge ${s.status === "used" ? "badge_good" : "badge_muted"}`,
      missingText: s.missing ?? ""
    }));
  }
  get usedCount() {
    return this.sources.filter((s) => s.status === "used").length;
  }
  get hasPerf() {
    return Boolean(this.perf);
  }
  get page() {
    return this.facts(this.report?.page);
  }
  get permissions() {
    return this.facts(this.report?.permissions);
  }
  facts(list) {
    return (list ?? []).map((f, i) => ({
      ...f,
      key: `${i}-${f.label}`,
      valueClass: `fact-value${f.tone === "bad" ? " fact-value_bad" : f.tone === "good" ? " fact-value_good" : ""}`
    }));
  }

  // ---- Performance --------------------------------------------------------------

  // What the browser logged, as figures. The load is timed from the card
  // connecting to the page until its days are painted.
  get measures() {
    const find = (pattern) => this.lines.find((l) => pattern.test(l.text));
    const grab = (line, pattern) => {
      const m = line ? pattern.exec(line.text) : null;
      return m ? Number(m[1]) : null;
    };
    const returned = find(/getTimeline returned/);
    const painted = grab(find(/first paint of the days/), /(\d+) ms after connecting/);
    const roundTrip = grab(returned, /returned (\d+) ms/);
    // The server's own figure for the request the card made.
    const server = this.perf?.serverMs ?? grab(returned, /\(server (\d+) ms/);
    return { painted, roundTrip, server };
  }

  get loaded() {
    return this.measures.painted !== null;
  }

  // The wait in three parts. The network's is the round trip less the server's
  // run: the answer getting there and back, which includes the platform handling
  // the request, so it is approximate. The browser's is the rest of the wait:
  // before the request went out, and drawing the answer.
  get parts() {
    const { painted, roundTrip, server } = this.measures;
    const total = painted ?? roundTrip;
    if (total === null || server === null) return null;
    const network = roundTrip === null ? 0 : Math.max(0, roundTrip - server);
    const browser = Math.max(0, total - server - network);
    return { total, server, network, browser, queries: this.perf?.queryCount };
  }

  get headline() {
    const { painted } = this.measures;
    const parts = this.parts;
    const tile = (key, label, value, note, className) => ({
      key,
      label,
      value: value === null || value === undefined ? "…" : seconds(value),
      note,
      className: `big ${className}${value === null || value === undefined ? " big_waiting" : ""}`
    });
    return [
      tile("total", "Load time (total)", parts?.total ?? null, painted === null ? "Waiting for the days to draw." : "From the page asking to the days on screen.", "big_total"),
      tile("server", "Server time (Apex)", parts?.server ?? null, "The server's run for this request.", "big_server"),
      tile("network", "Network time (approx.)", parts?.network ?? null, "The answer getting there and back, less the server's run. Includes the platform handling it.", "big_network"),
      tile("browser", "Browser time", parts?.browser ?? null, "Waiting to send the request, and drawing the answer.", "big_browser")
    ];
  }

  // A stacked bar of the wait: the server, the network, the browser.
  get shares() {
    const parts = this.parts;
    if (!parts || parts.total <= 0) return [];
    const part = (key, label, ms, className) => ({
      key,
      label,
      ms: seconds(ms),
      className: `share ${className}`,
      style: `width: ${Math.max(1, Math.round((ms / parts.total) * 100))}%`,
      legendClass: `swatch ${className}`
    });
    return [
      part("server", "Server (Apex)", parts.server, "share_server"),
      part("network", "Network (approx.)", parts.network, "share_network"),
      part("browser", "Browser", parts.browser, "share_browser")
    ];
  }
  get hasShares() {
    return this.shares.length > 0;
  }

  // In a sentence anyone can follow.
  get sentence() {
    const parts = this.parts;
    if (!parts) return "";
    const q = parts.queries;
    return `You waited ${seconds(parts.total)}. The server spent ${seconds(parts.server)} of that${q ? ` (${q} queries)` : ""}, the network about ${seconds(parts.network)}, and the browser ${seconds(parts.browser)}. Network and browser together are the ${seconds(parts.network + parts.browser)} that isn't the server.`;
  }

  get stats() {
    const t = this.perf;
    if (!t) return [];
    return [
      { key: "cpu", label: "Server CPU", value: `${t.cpuMs} ms` },
      { key: "q", label: "SOQL queries", value: `${t.queryCount} of 100` },
      { key: "rows", label: "Query rows", value: `${t.queryRows}` },
      { key: "size", label: "Response size", value: `${t.payloadKb} KB` },
      { key: "days", label: "Days with items", value: `${t.days}` },
      { key: "items", label: "Items on the first screen", value: `${t.events}` }
    ];
  }

  get queries() {
    return (this.perf?.queries ?? []).map((q) => ({
      ...q,
      key: `${q.seq}`,
      className: `row${q.error ? " row_error" : q.ms > SLOW_MS ? " row_slow" : ""}`,
      binds: q.binds || "none",
      rowsText: q.rows === null || q.rows === undefined ? "" : String(q.rows),
      short: q.soql.length > 120 ? `${q.soql.slice(0, 117)}…` : q.soql
    }));
  }
  get hasQueries() {
    return this.queries.length > 0;
  }
  get queryTotal() {
    return this.queries.reduce((sum, q) => sum + q.ms, 0);
  }

  // Time by source, from this request's queries and phases; the sources are named
  // from the Config tab's list.
  get bySource() {
    const names = new Map((this.report?.sources ?? []).map((s) => [s.developerName, s.label]));
    const counted = new Set(this.perf?.counted ?? []);
    const rows = new Map();
    const row = (name) => {
      if (!rows.has(name)) rows.set(name, { key: name, label: names.get(name) ?? name, queries: 0, queryMs: 0, rows: 0, sourceMs: 0 });
      return rows.get(name);
    };
    for (const q of this.perf?.queries ?? []) {
      if (q.source?.startsWith("(")) continue;
      const r = row(q.source);
      r.queries += 1;
      r.queryMs += q.ms;
      r.rows += q.rows ?? 0;
    }
    for (const p of this.perf?.phases ?? []) row(p.source).sourceMs += p.ms;
    return [...rows.values()].map((r) => ({
      ...r,
      how: counted.has(r.key) ? "counted, then rows" : "rows only",
      className: `row${r.sourceMs > SLOW_MS ? " row_slow" : ""}`
    }));
  }

  get notes() {
    return (this.perf?.notes ?? []).map((n, i) => ({ ...n, key: `${i}` }));
  }
  get hasNotes() {
    return this.notes.length > 0;
  }
  get problems() {
    const out = [];
    (this.perf?.problems ?? []).forEach((p, i) => out.push({ key: `p${i}`, text: p }));
    (this.perf?.warnings ?? []).forEach((w, i) => out.push({ key: `w${i}`, text: w }));
    return out;
  }
  get hasProblems() {
    return this.problems.length > 0;
  }

  get browserLines() {
    const first = this.lines[0]?.at ?? 0;
    return this.lines.map((l, i) => ({ key: `${i}`, at: Math.round(l.at - first), text: l.text }));
  }
  get hasBrowserLines() {
    return this.lines.length > 0;
  }
}
