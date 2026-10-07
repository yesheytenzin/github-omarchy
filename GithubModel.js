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

// "mine" = personal repos, "orgs" = organizations. A state file written by an
// older build may still say "all"; it clamps to personal, the same silent
// fallback every unknown value gets.
function clampScope(value) {
  return value === "orgs" ? "orgs" : "mine"
}

function clampTab(value) {
  if (value === "prs") return "prs"
  if (value === "repos") return "repos"
  return "issues"
}

function emptyRepoBucket() {
  return { count: 0, truncated: false, items: [] }
}

// The helper buckets repos by who owns them, so the scope chips can label
// themselves and the list can filter without re-deriving anything.
function emptyRepoField() {
  return { mine: emptyRepoBucket(), orgs: emptyRepoBucket() }
}

function normalizeRepo(raw) {
  if (!isObject(raw)) return null
  var name = String(raw.nameWithOwner || "")
  var url = String(raw.url || "")
  if (name === "" && url === "") return null
  return {
    kind: "repo",
    nameWithOwner: name !== "" ? name : url,
    url: url !== "" ? url : "https://github.com/" + name,
    scope: raw.scope === "orgs" ? "orgs" : "mine",
    pushedAt: String(raw.pushedAt || ""),
    pushedAtMs: Date.parse(String(raw.pushedAt || "")) || 0,
    starred: raw.starred === true
  }
}

function normalizeRepoBucket(scope, raw) {
  var bucket = emptyRepoBucket()
  if (!isObject(raw)) return bucket
  bucket.count = Number(raw.count || 0)
  bucket.truncated = raw.truncated === true
  if (Array.isArray(raw.items)) {
    for (var i = 0; i < raw.items.length; i++) {
      var repo = normalizeRepo(raw.items[i])
      if (!repo) continue
      // The bucket is the authority on where a repo belongs; the row only
      // carries the label.
      repo.scope = scope
      bucket.items.push(repo)
    }
  }
  if (bucket.count < bucket.items.length) bucket.count = bucket.items.length
  return bucket
}

function normalizeRepoField(raw) {
  if (!isObject(raw)) return emptyRepoField()
  return {
    mine: normalizeRepoBucket("mine", raw.mine),
    orgs: normalizeRepoBucket("orgs", raw.orgs)
  }
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
  return {
    type: raw.type === "pr" ? "pr" : "issue",
    scope: raw.scope === "orgs" ? "orgs" : "mine",
    number: Number(raw.number || 0),
    title: String(raw.title || "(no title)"),
    url: String(raw.url),
    repo: String(raw.repo || ""),
    updatedAt: String(raw.updatedAt || ""),
    updatedAtMs: Date.parse(String(raw.updatedAt || "")) || 0,
    authored: raw.authored === true,
    reviewRequested: raw.reviewRequested === true,
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
      scopes: emptyScopes(),
      repos: emptyRepoField()
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
    },
    repos: normalizeRepoField(parsed.repos)
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

// Pull requests read in three groups — yours, then the ones waiting on your
// review, then everything else that involves you — newest first inside each.
// Issues stay in plain recency order.
function prRank(item) {
  if (item.authored) return 0
  if (item.reviewRequested) return 1
  return 2
}

function sortedForTab(items, tab) {
  var copy = items.slice()
  if (clampTab(tab) !== "prs") {
    copy.sort(function(a, b) { return b.updatedAtMs - a.updatedAtMs })
    return copy
  }
  copy.sort(function(a, b) {
    var byGroup = prRank(a) - prRank(b)
    return byGroup !== 0 ? byGroup : b.updatedAtMs - a.updatedAtMs
  })
  return copy
}

function fieldFor(scopes, scope, tab) {
  var source = isObject(scopes) ? scopes : emptyScopes()
  var key = clampTab(tab)
  var bucket = clampScope(scope) === "orgs" ? source.orgs : source.mine
  var field = bucket && bucket[key] ? bucket[key] : emptyField()
  // The helper already sorts, but the panel must not depend on that: one
  // ordering rule here covers every scope.
  return { count: field.count, items: sortedForTab(field.items, key), truncated: field.truncated }
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
  var bucket = clampScope(scope) === "orgs" ? counts.orgs : counts.mine
  return bucket.issues + bucket.prs
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
  var bucket = clampScope(scope) === "orgs" ? counts.orgs : counts.mine
  var issues = bucket.issues
  var prs = bucket.prs
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

// ---- repos ----------------------------------------------------------------
//
// The repos view is a different list from the issue/PR searches: one bucket
// per scope. "Personal" shows the account's own repos, "Orgs" the repos owned
// by the organizations the viewer can reach.

// Starred first, freshest push next, then name. One comparator, not three
// stable passes: this engine's Array.sort does not promise stability, so
// equal-keyed rows would come back in arbitrary order.
function compareRepos(a, b) {
  if (a.starred !== b.starred) return a.starred ? -1 : 1
  if (a.pushedAtMs !== b.pushedAtMs) return b.pushedAtMs - a.pushedAtMs
  return a.nameWithOwner.toLowerCase() < b.nameWithOwner.toLowerCase() ? -1
    : (a.nameWithOwner.toLowerCase() > b.nameWithOwner.toLowerCase() ? 1 : 0)
}

function reposFor(repos, scope) {
  var field = isObject(repos) ? repos : emptyRepoField()
  var bucket = clampScope(scope) === "orgs" ? (field.orgs || emptyRepoBucket()) : (field.mine || emptyRepoBucket())
  var items = []
  for (var i = 0; i < bucket.items.length; i++) items.push(bucket.items[i])
  items.sort(compareRepos)
  return items
}

function bucketCount(bucket) {
  if (!isObject(bucket)) return 0
  var declared = Number(bucket.count || 0)
  var shown = Array.isArray(bucket.items) ? bucket.items.length : 0
  // The declared total wins while it is larger; the rows win when a payload
  // arrives without counts at all.
  return Math.max(declared, shown)
}

function repoCountFor(repos, scope) {
  var field = isObject(repos) ? repos : emptyRepoField()
  return bucketCount(clampScope(scope) === "orgs" ? field.orgs : field.mine)
}

function repoMeta(repos, scope, fetchedAtSec, loading, nowMs) {
  var label = plural(repoCountFor(repos, scope), "repo", "repos")
  if (loading) return "refreshing — " + label
  if (!fetchedAtSec) return label
  var age = relativeTime(fetchedAtSec * 1000, nowMs)
  return label + (age === "now" ? " · updated just now" : " · updated " + age + " ago")
}

// The second line of a repo row: what is open there, and when it last moved.
function reposTruncationHint(repos, scope) {
  var field = isObject(repos) ? repos : emptyRepoField()
  var bucket = clampScope(scope) === "orgs" ? (field.orgs || emptyRepoBucket()) : (field.mine || emptyRepoBucket())
  var shown = Array.isArray(bucket.items) ? bucket.items.length : 0
  var total = bucketCount(bucket)
  if (bucket.truncated !== true || total <= shown) return ""
  return "Showing the most recent " + shown + " of " + total + "."
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
