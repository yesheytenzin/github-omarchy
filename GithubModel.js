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

function clampScope(value) {
  return value === "all" ? "all" : "mine"
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
    needsMe: raw.needsMe === true
  }
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
  if (clampScope(scope) === "mine") {
    var mine = source.mine ? source.mine[key] : emptyField()
    // The helper already sorts, but the panel must not depend on that: one
    // ordering rule here covers both scopes.
    return { count: mine.count, items: sortedByUpdated(mine.items), truncated: mine.truncated }
  }
  var mineField = source.mine ? source.mine[key] : emptyField()
  var orgField = source.orgs ? source.orgs[key] : emptyField()
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
  if (clampScope(scope) === "mine") return counts.mine.issues + counts.mine.prs
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
  var issues = counts.mine.issues + (clampScope(scope) === "all" ? counts.orgs.issues : 0)
  var prs = counts.mine.prs + (clampScope(scope) === "all" ? counts.orgs.prs : 0)
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
