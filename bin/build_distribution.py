#!/usr/bin/env python3
"""Companion distribution views for depgraph/data.json -> distribution.html.

Self-contained (no libraries). Characterises the binary-block size distribution
and flags "bizarre" packages (large own-code but few consumers). Chart toggle:
Rank-size (Zipf), Pareto, Size vs consumers, ECDF. A stats readout (median / p90
/ p95 / p99 / Gini / top-5 share) sits in the header; dark/light theme toggle.
"""
import json, os
from pathlib import Path

DATA = Path(os.environ.get("DEPMAP_DATA", "data.json")).resolve()
OUT = Path(os.environ.get("DEPMAP_DIST", "distribution.html")).resolve()
data = json.loads(DATA.read_text())
PROJECT = data.get("project") or "project"

HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Dream &mdash; package size distribution</title>
<style>
  :root { font-family: ui-sans-serif, system-ui, sans-serif; }
  html, body { height: 100%; }
  body { margin: 0; height: 100vh; overflow: hidden; display: flex; flex-direction: column;
         background: var(--bg); color: var(--fg);
         --bg:#0f1116; --panel:#0b0d12; --fg:#d7dae0; --muted:#8b93a1; --faint:#6b7280;
         --border:#242832; --hair:#39404e; --grid:#20242e; --btnbg:#1b1f29; --btnhover:#262c38;
         --btnactive:#3a4252; --btnfg:#c0c7d4; --btnactivefg:#fff; --btnactiveborder:#6b7686;
         --tipbg:#1b1f29; --dot:#6f8bbd; --accent:#4a9eff; --bizarre:#ff6b6b; }
  body.light { --bg:#eef1f5; --panel:#ffffff; --fg:#1b1f27; --muted:#56606e; --faint:#8793a2;
         --border:#d2d8e0; --hair:#c2c9d4; --grid:#e3e8ef; --btnbg:#e7ebf1; --btnhover:#dbe1ea;
         --btnactive:#c9d3e2; --btnfg:#2b323d; --btnactivefg:#0a0d12; --btnactiveborder:#8ea0b8;
         --tipbg:#ffffff; --dot:#46618f; --accent:#1f6fd6; --bizarre:#d63b3b; }
  header { padding: 10px 16px; border-bottom: 1px solid var(--border); flex: 0 0 auto; }
  h1 { font-size: 15px; margin: 0 0 3px; font-weight: 600; }
  .stats { font-size: 12px; color: var(--muted); }
  .stats b { color: var(--fg); font-weight: 600; }
  #bar { padding: 5px 16px; font-size: 11px; color: var(--muted); display: flex; gap: 5px;
         align-items: center; flex-wrap: wrap; flex: 0 0 auto; }
  .lbl { color: var(--faint); margin-right: 3px; }
  button { font: inherit; font-size: 11px; color: var(--btnfg); background: var(--btnbg);
           border: 1px solid var(--hair); border-radius: 4px; padding: 2px 8px; cursor: pointer; }
  button:hover { background: var(--btnhover); }
  button.active { background: var(--btnactive); color: var(--btnactivefg); border-color: var(--btnactiveborder); }
  .swatch { display: inline-block; width: 9px; height: 9px; border-radius: 50%; vertical-align: -1px; margin: 0 3px 0 8px; }
  #wrap { position: relative; margin: 6px 16px; border: 1px solid var(--border); border-radius: 6px;
          overflow: hidden; background: var(--panel); flex: 1 1 auto; min-height: 0; }
  svg { position: absolute; inset: 0; width: 100%; height: 100%; }
  text { fill: var(--fg); }
  .axis line, .axis path { stroke: var(--hair); }
  .grid line { stroke: var(--grid); }
  .tick { fill: var(--muted); font-size: 10px; }
  .albl { fill: var(--muted); font-size: 11px; }
  .pt { fill: var(--dot); }
  .pt.biz { fill: var(--bizarre); }
  .plabel { fill: var(--fg); font-size: 10px; }
  #tip { position: fixed; pointer-events: none; z-index: 50; background: var(--tipbg); color: var(--fg);
         border: 1px solid var(--hair); border-radius: 6px; padding: 7px 9px; font-size: 12px;
         display: none; box-shadow: 0 6px 20px rgba(0,0,0,.4); }
  #tip .k { color: var(--muted); }
  footer { padding: 6px 16px 16px; font-size: 11px; color: var(--faint); max-width: 1000px; flex: 0 0 auto; }
</style>
</head>
<body>
<header>
  <h1>Dream &mdash; binary-block size distribution</h1>
  <div class="stats" id="stats"></div>
</header>
<div id="bar"></div>
<div id="wrap"><svg id="svg"></svg></div>
<div id="tip"></div>
<footer id="method"></footer>
<script>
const DATA = __DATA__;
const SELF = new Map(), KIND = new Map();
for (const n of DATA.nodes) { SELF.set(n.id, n.self); KIND.set(n.id, n.kind); }
const indeg = new Map(), outdeg = new Map();
for (const [a, b] of DATA.edges) { outdeg.set(a, (outdeg.get(a) || 0) + 1); indeg.set(b, (indeg.get(b) || 0) + 1); }
// binary blocks = external + Dream libs that emit code
const B = DATA.nodes.filter(n => n.kind === "external" || (n.kind === "own" && n.self > 0))
  .map(n => ({ id: n.id, size: Math.max(n.self, 1), cons: indeg.get(n.id) || 0, deps: outdeg.get(n.id) || 0, kind: n.kind }));
const N = B.length;

// ---- stats -----------------------------------------------------------------
const sizes = B.map(d => d.size).sort((a, b) => a - b);
const total = sizes.reduce((s, x) => s + x, 0);
const q = p => sizes[Math.min(N - 1, Math.max(0, Math.round(p * (N - 1))))];
const median = q(0.5);
const gini = (() => { let s = 0; for (let i = 0; i < N; i++) s += (i + 1) * sizes[i]; return (2 * s) / (N * total) - (N + 1) / N; })();
const top5 = sizes.slice(-5).reduce((s, x) => s + x, 0);
function fmtB(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + " MiB" : b >= 1024 ? Math.round(b / 1024) + " KiB" : b + " B"; }
const SMIN = Math.pow(10, Math.floor(Math.log10(sizes[0]))), SMAX = Math.pow(10, Math.ceil(Math.log10(sizes[N - 1])));

// ---- "bizarre": large own-code but few consumers ---------------------------
// score = size / (consumers + 1); flag the worst few above the median size.
const BIZ_N = 8;
const bizRanked = B.filter(d => d.size > median).sort((a, b) => b.size / (b.cons + 1) - a.size / (a.cons + 1));
const bizarre = new Set(bizRanked.slice(0, BIZ_N).map(d => d.id));

document.getElementById("stats").innerHTML =
  `n=<b>${N}</b> blocks &nbsp; total=<b>${fmtB(total)}</b> &nbsp; median=<b>${fmtB(median)}</b> &nbsp; `
  + `p90=<b>${fmtB(q(0.9))}</b> &nbsp; p95=<b>${fmtB(q(0.95))}</b> &nbsp; p99=<b>${fmtB(q(0.99))}</b> &nbsp; `
  + `Gini=<b>${gini.toFixed(2)}</b> &nbsp; top-5=<b>${Math.round(100 * top5 / total)}%</b> of bytes`;

// ---- scales / svg helpers --------------------------------------------------
const NS = "http://www.w3.org/2000/svg";
const svg = document.getElementById("svg"), tip = document.getElementById("tip");
function el(tag, at, parent) { const e = document.createElementNS(NS, tag); for (const k in at) e.setAttribute(k, at[k]); if (parent) parent.appendChild(e); return e; }
const lin = (d0, d1, r0, r1) => v => r0 + (v - d0) / (d1 - d0 || 1) * (r1 - r0);
const log = (d0, d1, r0, r1) => { const a = Math.log10(d0), b = Math.log10(d1); return v => r0 + (Math.log10(v) - a) / (b - a || 1) * (r1 - r0); };
function logTicks(min, max) { const t = []; for (let k = Math.floor(Math.log10(min)); k <= Math.ceil(Math.log10(max)); k++) { const p = Math.pow(10, k); if (p >= min / 2 && p <= max * 2) t.push(p); } return t; }
function linTicks(min, max, n) { const step = niceStep((max - min) / n); const t = []; for (let v = Math.ceil(min / step) * step; v <= max + 1e-9; v += step) t.push(Math.round(v)); return t; }
function niceStep(s) { const p = Math.pow(10, Math.floor(Math.log10(s))), r = s / p; return (r < 1.5 ? 1 : r < 3 ? 2 : r < 7 ? 5 : 10) * p; }
function showTip(e, html) { tip.innerHTML = html; tip.style.display = "block"; tip.style.left = Math.min(e.clientX + 13, innerWidth - 230) + "px"; tip.style.top = Math.min(e.clientY + 13, innerHeight - 80) + "px"; }
const hideTip = () => tip.style.display = "none";
const ptTip = d => `<b>${d.id}</b>${bizarre.has(d.id) ? ' <span style="color:var(--bizarre)">bizarre</span>' : ''}<br><span class="k">own code</span> ${fmtB(d.size)}<br><span class="k">consumers</span> ${d.cons} &nbsp; <span class="k">deps</span> ${d.deps}`;

let chart = "scatter";

// ---- charts ----------------------------------------------------------------
function frame() {
  svg.innerHTML = "";
  const W = wrap.clientWidth, H = wrap.clientHeight;
  svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
  const m = { t: 18, r: 54, b: 42, l: 60 };
  return { W, H, m, x0: m.l, x1: W - m.r, y0: H - m.b, y1: m.t, pw: W - m.l - m.r, ph: H - m.t - m.b };
}
function yAxisLog(f, min, max, title) {
  const g = el("g", { class: "grid" }, svg);
  for (const t of logTicks(min, max)) { const y = f.ySc(t); el("line", { x1: f.x0, x2: f.x1, y1: y, y2: y }, g); el("text", { x: f.x0 - 8, y: y + 3, "text-anchor": "end", class: "tick" }, svg).textContent = fmtB(t); }
  el("text", { x: 14, y: (f.y0 + f.y1) / 2, class: "albl", "text-anchor": "middle", transform: `rotate(-90 14 ${(f.y0 + f.y1) / 2})` }, svg).textContent = title;
}
function xTicks(f, scale, ticks, fmt, title) {
  const g = el("g", { class: "grid" }, svg);
  for (const t of ticks) { const x = scale(t); el("line", { x1: x, x2: x, y1: f.y0, y2: f.y1 }, g); el("text", { x, y: f.y0 + 16, "text-anchor": "middle", class: "tick" }, svg).textContent = fmt(t); }
  el("text", { x: (f.x0 + f.x1) / 2, y: f.y0 + 34, class: "albl", "text-anchor": "middle" }, svg).textContent = title;
}
function point(d, x, y, r) {
  const c = el("circle", { cx: x, cy: y, r: r || (bizarre.has(d.id) ? 4.5 : 3), class: "pt" + (bizarre.has(d.id) ? " biz" : "") }, svg);
  c.addEventListener("mousemove", e => showTip(e, ptTip(d))); c.addEventListener("mouseleave", hideTip);
  if (bizarre.has(d.id)) el("text", { x: x + 6, y: y + 3, class: "plabel" }, svg).textContent = d.id;
}

function drawScatter(f) {
  const maxC = Math.max(...B.map(d => d.cons));
  const xSc = lin(0, maxC, f.x0, f.x1), ySc = log(SMIN, SMAX, f.y0, f.y1); f.ySc = ySc;
  yAxisLog(f, SMIN, SMAX, "own code");
  xTicks(f, xSc, linTicks(0, maxC, 6), v => v, "consumers (in-degree)");
  // "bizarre" region hint: big & few consumers (top-left)
  el("text", { x: f.x0 + 6, y: f.y1 + 12, class: "albl", fill: "var(--bizarre)" }, svg).textContent = "← big & few consumers = bizarre";
  for (const d of B) if (!bizarre.has(d.id)) point(d, xSc(d.cons), ySc(d.size));
  for (const d of B) if (bizarre.has(d.id)) point(d, xSc(d.cons), ySc(d.size));
}
function drawRankSize(f) {
  const s = B.slice().sort((a, b) => b.size - a.size);
  const xSc = log(1, N, f.x0, f.x1), ySc = log(SMIN, SMAX, f.y0, f.y1); f.ySc = ySc;
  yAxisLog(f, SMIN, SMAX, "own code");
  xTicks(f, xSc, logTicks(1, N).concat([N]), v => v, "rank (largest → smallest)");
  s.forEach((d, i) => point(d, xSc(i + 1), ySc(d.size)));
}
function drawECDF(f) {
  const xSc = log(SMIN, SMAX, f.x0, f.x1), ySc = lin(0, 1, f.y0, f.y1); f.ySc = ySc;
  // y grid 0..1
  const gg = el("g", { class: "grid" }, svg);
  for (let p = 0; p <= 1.0001; p += 0.25) { const y = ySc(p); el("line", { x1: f.x0, x2: f.x1, y1: y, y2: y }, gg); el("text", { x: f.x0 - 8, y: y + 3, "text-anchor": "end", class: "tick" }, svg).textContent = Math.round(p * 100) + "%"; }
  xTicks(f, xSc, logTicks(SMIN, SMAX), fmtB, "own code (log)");
  let dpath = `M ${f.x0} ${ySc(0)}`;
  sizes.forEach((v, i) => { const x = xSc(v), y = ySc((i + 1) / N); dpath += ` L ${x} ${ySc(i / N)} L ${x} ${y}`; });
  el("path", { d: dpath, fill: "none", stroke: "var(--accent)", "stroke-width": 1.6 }, svg);
  for (const [p, lbl] of [[0.5, "p50"], [0.9, "p90"], [0.95, "p95"], [0.99, "p99"]]) {
    const x = xSc(q(p)), y = ySc(p);
    el("line", { x1: x, x2: x, y1: f.y0, y2: y, stroke: "var(--muted)", "stroke-dasharray": "3 3" }, svg);
    el("text", { x: x + 3, y: y - 3, class: "plabel" }, svg).textContent = `${lbl} ${fmtB(q(p))}`;
  }
}
function drawPareto(f) {
  const s = B.slice().sort((a, b) => b.size - a.size);
  const xSc = lin(0, N, f.x0, f.x1), ySc = lin(0, s[0].size, f.y0, f.y1), cSc = lin(0, 1, f.y0, f.y1);
  f.ySc = ySc;
  // left axis (size) grid
  const gg = el("g", { class: "grid" }, svg);
  for (const t of linTicks(0, s[0].size, 5)) { const y = ySc(t); el("line", { x1: f.x0, x2: f.x1, y1: y, y2: y }, gg); el("text", { x: f.x0 - 8, y: y + 3, "text-anchor": "end", class: "tick" }, svg).textContent = fmtB(t); }
  // right axis (cumulative %)
  for (let p = 0; p <= 1.0001; p += 0.25) { const y = cSc(p); el("text", { x: f.x1 + 8, y: y + 3, "text-anchor": "start", class: "tick" }, svg).textContent = Math.round(p * 100) + "%"; }
  xTicks(f, xSc, linTicks(0, N, 6), v => v, "rank");
  const bw = Math.max(1, f.pw / N - 1);
  let cum = 0; const linePts = [];
  s.forEach((d, i) => {
    const x = xSc(i), y = ySc(d.size);
    const rc = el("rect", { x: x, y: y, width: bw, height: f.y0 - y, fill: bizarre.has(d.id) ? "var(--bizarre)" : "var(--dot)", opacity: .85 }, svg);
    rc.addEventListener("mousemove", e => showTip(e, ptTip(d))); rc.addEventListener("mouseleave", hideTip);
    cum += d.size; linePts.push([xSc(i + 1), cSc(cum / total)]);
  });
  el("path", { d: "M " + linePts.map(p => p.join(" ")).join(" L "), fill: "none", stroke: "var(--accent)", "stroke-width": 1.6 }, svg);
  // 80% guide
  const y80 = cSc(0.8); el("line", { x1: f.x0, x2: f.x1, y1: y80, y2: y80, stroke: "var(--muted)", "stroke-dasharray": "4 3" }, svg);
  let k = 0, c2 = 0; for (const d of s) { c2 += d.size; k++; if (c2 / total >= 0.8) break; }
  el("text", { x: f.x1 - 4, y: y80 - 4, "text-anchor": "end", class: "plabel" }, svg).textContent = `80% of bytes = top ${k} blocks`;
  el("text", { x: f.x1 + 8, y: f.y1 + 6, class: "albl", "text-anchor": "start" }, svg).textContent = "cumulative";
}

const CHARTS = { scatter: drawScatter, ranksize: drawRankSize, ecdf: drawECDF, pareto: drawPareto };
const wrap = document.getElementById("wrap");
function render() { const f = frame(); CHARTS[chart](f); }

// ---- toolbar ---------------------------------------------------------------
const bar = document.getElementById("bar");
function buildBar() {
  bar.innerHTML = "";
  const l1 = document.createElement("span"); l1.className = "lbl"; l1.textContent = "Chart:"; bar.appendChild(l1);
  for (const [k, lab] of [["scatter", "Size vs consumers"], ["ranksize", "Rank-size"], ["pareto", "Pareto"], ["ecdf", "ECDF"]]) {
    const b = document.createElement("button"); b.textContent = lab; b.className = (k === chart ? "active" : "");
    b.onclick = () => { chart = k; render(); buildBar(); }; bar.appendChild(b);
  }
  const key = document.createElement("span"); key.style.marginLeft = "6px";
  key.innerHTML = `<span class="swatch" style="background:var(--dot)"></span>package <span class="swatch" style="background:var(--bizarre)"></span>bizarre (big &amp; few consumers)`;
  bar.appendChild(key);
  const l2 = document.createElement("span"); l2.className = "lbl"; l2.style.marginLeft = "10px"; l2.textContent = "Theme:"; bar.appendChild(l2);
  for (const [k, lab] of [["dark", "Dark"], ["light", "Light"]]) {
    const on = (k === "light") === document.body.classList.contains("light");
    const b = document.createElement("button"); b.textContent = lab; b.className = (on ? "active" : "");
    b.onclick = () => { document.body.classList.toggle("light", k === "light"); render(); buildBar(); }; bar.appendChild(b);
  }
}
document.getElementById("method").innerHTML =
  "<b>Method.</b> One mark per binary block (external library or Dream lib with code), own compiled-"
  + "artifact bytes. Sizes are heavy-tailed (mean &gt; median, Gini shown), so raw-size outlier fences "
  + "just re-flag the tail &mdash; <b>bizarre</b> instead means <b>large own-code but few consumers</b> "
  + "(size &divide; (consumers+1), top " + BIZ_N + " above the median), the top-left of the scatter. "
  + "<i>Size vs consumers</i> isolates that; <i>Rank-size</i> (log-log) shows the tail and deviations; "
  + "<i>Pareto</i> shows concentration (how few blocks make 80% of bytes); <i>ECDF</i> reads any "
  + "quantile. Companion to the dependency map (squarified_treemap.html).";

buildBar();
render();
new ResizeObserver(() => render()).observe(wrap);
addEventListener("resize", render);
</script>
</body>
</html>
"""

out = HTML.replace("__DATA__", json.dumps(data, separators=(",", ":"))).replace("Dream", PROJECT)
OUT.write_text(out)
print("wrote %s  (%d bytes)" % (OUT, len(out)))
