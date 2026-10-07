.pragma library

// Shaping for the github-oma service and panel: everything that turns the
// helper's JSON into rows, counts, and strings lives here so the QML files
// stay layout-only and this logic stays testable from qml6 without a shell.
//
// The shape this module speaks (produced by bin/github-oma):
//
//   { ok, cached, fetchedAt, login, orgs, scopes: {
//       mine: { issues: field, prs: field }, orgs: { issues: field, prs: field } } }
//   field = { count, items: [item], truncated }
//   item  = { type, scope, number, title, url, repo, updatedAt, draft,
//             reviewDecision, labels: [{name, color}], comments,
//             assignees: [login], reviewers: [login], needsMe }

function emptyField() {
  return { count: 0, items: [], truncated: false }
}

function emptyScopes() {
  return {
    mine: { issues: emptyField(), prs: emptyField() },
    orgs: { issues: emptyField(), prs: emptyField() }
  }
}

// "mine" = personal repos only, "orgs" = organizations only, "all" = both
// merged. The panel's scope chips cycle through the three.
function clampScope(value) {
  if (value === "all") return "all"
  if (value === "orgs") return "orgs"
  return "mine"
}

function clampTab(value) {
  return value === "prs" ? "prs" : "issues"
}

function isObject(value) {
  return value !== null && typeof value === "object"
}

function normalizeField(raw) {
  var field = emptyField()
  if (!isObject(raw)) return field
  field.count = Number(raw.count || 0)
  field.truncated = raw.truncated === true
  if (Array.isArray(raw.items)) {
    for (var i = 0; i < raw.items.length; i++) {
      var item = normalizeItem(raw.items[i])
      if (item) field.items.push(item)
    }
  }
  if (field.count < field.items.length) field.count = field.items.length
  return field
}

function normalizeItem(raw) {
  if (!isObject(raw) || typeof raw.url !== "string" || raw.url === "") return null
  var labels = []
  if (Array.isArray(raw.labels)) {
    for (var i = 0; i < raw.labels.length && labels.length < 3; i++) {
      var label = raw.labels[i]
      if (isObject(label) && String(label.name || "") !== "") {
        labels.push({ name: String(label.name), color: String(label.color || "") })
      }
    }
  }
  return {
    type: raw.type === "pr" ? "pr" : "issue",
    scope: raw.scope === "orgs" ? "orgs" : "mine",
    number: Number(raw.number || 0),
    title: String(raw.title || "(no title)"),
    url: String(raw.url),
    repo: String(raw.repo || ""),
    updatedAt: String(raw.updatedAt || ""),
    updatedAtMs: Date.parse(String(raw.updatedAt || "")) || 0,
    draft: raw.draft === true,
    reviewDecision: String(raw.reviewDecision || ""),
    labels: labels,
    comments: Number(raw.comments || 0),
    assigned: raw.assigned === true,
    reviewRequested: raw.reviewRequested === true,
    needsMe: raw.needsMe === true || raw.assigned === true || raw.reviewRequested === true
  }
}

// ---- state colouring ------------------------------------------------------
//
// Tones, worst first. The panel maps a tone to one theme-aware colour (and
// tints the chip from it); keeping the names here means the rules are
// testable without a running shell.
//
//   urgent   something is wrong or waiting on you hard (red)
//   warning  a review has to happen before it can move (yellow)
//   success  approved and moving (green)
//   accent   yours, but not blocked (the theme accent)
//   dim      parked: drafts, and rows with nothing to say

var TONES = ["dim", "accent", "success", "warning", "urgent"]

function toneRank(tone) {
  var index = TONES.indexOf(String(tone || ""))
  return index < 0 ? 0 : index
}

function worseTone(a, b) {
  return toneRank(a) >= toneRank(b) ? a : b
}

// The review state of a pull request: what the PR is waiting for.
function stateChip(item) {
  if (!item || item.type !== "pr") return null
  if (item.draft) return { label: "DRAFT", tone: "dim" }
  switch (item.reviewDecision) {
  case "APPROVED":
    return { label: "APPROVED", tone: "success" }
  case "CHANGES_REQUESTED":
    return { label: "CHANGES REQUESTED", tone: "urgent" }
  case "REVIEW_REQUIRED":
    return { label: "NEEDS REVIEW", tone: "warning" }
  default:
    return null
  }
}

// Why this row is yours: your review is the blocking one, or it is assigned
// to you. Shown on every row that has one, issues included.
function youChip(item) {
  if (!item) return null
  if (item.reviewRequested) return { label: "YOUR REVIEW", tone: "urgent" }
  if (item.assigned) return { label: "ASSIGNED", tone: "accent" }
  return null
}

// One tone for the row as a whole, used to colour the type glyph so a scan
// down the left edge reads the states without reading the chips.
function rowTone(item) {
  var tone = "dim"
  var state = stateChip(item)
  var you = youChip(item)
  if (state) tone = worseTone(tone, state.tone)
  if (you) tone = worseTone(tone, you.tone)
  return tone
}

// The whole payload or null. Anything unexpected is rejected rather than
// half-trusted: the panel shows a retry notice instead of a broken list.
//
// A failure payload carries no scopes — only the typed error the helper
// chose — so it is accepted here and handed on with empty scopes. Losing
// that type would turn "run gh auth login" into "unreadable reply".
function parseRefresh(raw) {
  var text = String(raw || "")
  var start = text.indexOf("{")
  if (start < 0) return null
  var parsed
  try {
    parsed = JSON.parse(text.slice(start))
  } catch (error) {
    return null
  }
  if (!isObject(parsed)) return null

  if (parsed.ok !== true) {
    if (typeof parsed.error !== "string" && typeof parsed.message !== "string") return null
    return {
      ok: false,
      cached: false,
      error: String(parsed.error || ""),
      message: String(parsed.message || ""),
      login: "",
      orgs: [],
      fetchedAt: Number(parsed.fetchedAt || 0),
      scopes: emptyScopes()
    }
  }

  if (!isObject(parsed.scopes)) return null
  if (!isObject(parsed.scopes.mine) || !isObject(parsed.scopes.orgs)) return null
  return {
    ok: true,
    cached: parsed.cached === true,
    error: "",
    message: "",
    login: String(parsed.login || ""),
    orgs: Array.isArray(parsed.orgs) ? parsed.orgs.map(function(name) { return String(name) }) : [],
    fetchedAt: Number(parsed.fetchedAt || 0),
    scopes: {
      mine: { issues: normalizeField(parsed.scopes.mine.issues), prs: normalizeField(parsed.scopes.mine.prs) },
      orgs: { issues: normalizeField(parsed.scopes.orgs.issues), prs: normalizeField(parsed.scopes.orgs.prs) }
    }
  }
}

function parseState(raw) {
  var state = { scope: "mine", tab: "issues" }
  var text = String(raw || "")
  if (text.trim() === "") return state
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (error) {
    return state
  }
  if (!isObject(parsed)) return state
  state.scope = clampScope(parsed.scope)
  state.tab = clampTab(parsed.tab)
  return state
}

function serializeState(scope, tab) {
  return JSON.stringify({ scope: clampScope(scope), tab: clampTab(tab) }, null, 2) + "\n"
}

function sortedByUpdated(items) {
  var copy = items.slice()
  copy.sort(function(a, b) { return b.updatedAtMs - a.updatedAtMs })
  return copy
}

function dedupe(items) {
  var seen = {}
  var result = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (seen[item.url]) continue
    seen[item.url] = true
    result.push(item)
  }
  return result
}

function fieldFor(scopes, scope, tab) {
  var source = isObject(scopes) ? scopes : emptyScopes()
  var key = clampTab(tab)
  var mineField = source.mine ? source.mine[key] : emptyField()
  var orgField = source.orgs ? source.orgs[key] : emptyField()
  var name = clampScope(scope)
  // The helper already sorts, but the panel must not depend on that: one
  // ordering rule here covers every scope.
  if (name === "mine") {
    return { count: mineField.count, items: sortedByUpdated(mineField.items), truncated: mineField.truncated }
  }
  if (name === "orgs") {
    return { count: orgField.count, items: sortedByUpdated(orgField.items), truncated: orgField.truncated }
  }
  return {
    count: mineField.count + orgField.count,
    items: sortedByUpdated(dedupe(mineField.items.concat(orgField.items))),
    truncated: mineField.truncated || orgField.truncated
  }
}

function itemsFor(scopes, scope, tab) {
  return fieldFor(scopes, scope, tab).items
}

function countsFor(scopes) {
  var counts = { mine: { issues: 0, prs: 0 }, orgs: { issues: 0, prs: 0 } }
  var source = isObject(scopes) ? scopes : emptyScopes()
  for (var i = 0; i < 2; i++) {
    var scope = i === 0 ? "mine" : "orgs"
    for (var j = 0; j < 2; j++) {
      var tab = j === 0 ? "issues" : "prs"
      var field = source[scope] ? source[scope][tab] : null
      counts[scope][tab] = field ? field.count : 0
    }
  }
  return counts
}

function badgeCount(scopes, scope) {
  var counts = countsFor(scopes)
  var name = clampScope(scope)
  if (name === "mine") return counts.mine.issues + counts.mine.prs
  if (name === "orgs") return counts.orgs.issues + counts.orgs.prs
  return counts.mine.issues + counts.mine.prs + counts.orgs.issues + counts.orgs.prs
}

function attentionCount(scopes, scope) {
  var total = 0
  for (var j = 0; j < 2; j++) {
    var items = itemsFor(scopes, scope, j === 0 ? "issues" : "prs")
    for (var i = 0; i < items.length; i++) if (items[i].needsMe) total++
  }
  return total
}

function plural(count, singular, pluralForm) {
  return count + " " + (count === 1 ? singular : pluralForm)
}

// The hero's one-line summary. PanelHero renders meta uppercase, so this
// stays lowercase: "4 issues · 2 pull requests · updated 2m ago".
function updatedMeta(scopes, scope, fetchedAtSec, loading, nowMs) {
  var counts = countsFor(scopes)
  var name = clampScope(scope)
  var withMine = name !== "orgs"
  var withOrgs = name !== "mine"
  var issues = (withMine ? counts.mine.issues : 0) + (withOrgs ? counts.orgs.issues : 0)
  var prs = (withMine ? counts.mine.prs : 0) + (withOrgs ? counts.orgs.prs : 0)
  var parts = [plural(issues, "issue", "issues"), plural(prs, "pull request", "pull requests")]
  var summary = parts.join(" · ")
  if (loading) return "refreshing — " + summary
  if (!fetchedAtSec) return summary
  var age = relativeTime(fetchedAtSec * 1000, nowMs)
  return summary + (age === "now" ? " · updated just now" : " · updated " + age + " ago")
}

function truncationHint(scopes, scope, tab) {
  var field = fieldFor(scopes, scope, tab)
  if (!field.truncated || field.count <= field.items.length) return ""
  return "Showing the most recent " + field.items.length + " of " + field.count + "."
}

function relativeTime(ms, nowMs) {
  if (!ms) return ""
  var seconds = Math.max(0, Math.round((nowMs - ms) / 1000))
  if (seconds < 60) return "now"
  var minutes = Math.round(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.round(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.round(hours / 24)
  if (days < 7) return days + "d"
  var weeks = Math.round(days / 7)
  if (weeks < 5) return weeks + "w"
  return Math.round(days / 30) + "mo"
}

// GitHub ships label colors as bare hex; the row draws a dot in that color
// and keeps the theme's foreground for text, so a label can never make a
// row unreadable on a theme whose accent contrasts badly.
function labelRgba(color, alpha) {
  var hex = String(color || "").replace("#", "")
  if (hex.length !== 6) return "rgba(128,128,128," + alpha + ")"
  var r = parseInt(hex.slice(0, 2), 16)
  var g = parseInt(hex.slice(2, 4), 16)
  var b = parseInt(hex.slice(4, 6), 16)
  if (isNaN(r) || isNaN(g) || isNaN(b)) return "rgba(128,128,128," + alpha + ")"
  return "rgba(" + r + "," + g + "," + b + "," + alpha + ")"
}

// One notice line per failure kind: what happened, then the exact fix.
function errorNotice(kind, message) {
  switch (String(kind || "")) {
  case "no-gh":
    return { title: "GitHub CLI not found",
             hint: "Install it with: sudo pacman -S github-cli — then press r" }
  case "no-auth":
    return { title: "Not signed in to GitHub",
             hint: "Run gh auth login in a terminal, then press r" }
  case "timeout":
    return { title: "GitHub did not answer in time", hint: "Press r to retry" }
  case "fetch-failed":
    return { title: "Could not reach GitHub", hint: "Press r to retry" }
  case "no-helper":
    return { title: "The plugin helper is missing", hint: "Reinstall the plugin: omarchy plugin remove tenzin.github-oma" }
  case "parse-failed":
    return { title: "Unreadable reply from the helper", hint: "Press r to retry" }
  default:
    return { title: String(message || "Something went wrong"), hint: "Press r to retry" }
  }
}
