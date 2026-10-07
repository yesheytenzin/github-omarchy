import QtQuick
import "../GithubModel.js" as Model
// Runs the plugin's shaping logic headlessly.
//
//   qml6 ModelTest.qml
//
// Exits 0 when every expectation holds and 1 otherwise, which is what
// tests/run.sh gates on. (qml6 swallows console.log, so failure detail only
// shows when the run is driven by hand.)
QtObject {
  id: root

  property int checks: 0
  property int failures: 0

  function expect(condition, message) {
    checks++
    if (!condition) {
      failures++
      console.error("FAIL: " + message)
    }
  }

  function expectEqual(actual, expected, message) {
    expect(String(actual) === String(expected),
           message + " (expected [" + expected + "], got [" + actual + "])")
  }

  function contains(haystack, needle, message) {
    expect(String(haystack).indexOf(needle) !== -1,
           message + " ([" + haystack + "] lacks [" + needle + "])")
  }

  Component.onCompleted: run()

  function run() {
    try {
      testParseRefresh()
      testRejects()
      testState()
      testCounts()
      testMerge()
      testStrings()
      testLabels()
      testNotices()
      testChips()
    } catch (error) {
      // A throw would otherwise leave qml6 running with nothing to exit it.
      failures++
      console.error("FAIL: threw " + error)
    }
    if (failures > 0) {
      console.error(failures + " of " + checks + " model checks failed")
      Qt.exit(1)
      return
    }
    Qt.exit(0)
  }

  // ---- fixtures -----------------------------------------------------------

  function item(url, updatedAt, extras) {
    var base = {
      type: "issue",
      scope: "mine",
      number: 1,
      title: "t",
      url: url,
      repo: "yesheytenzin/auto-workspace",
      updatedAt: updatedAt,
      labels: [],
      assignees: [],
      reviewers: [],
      needsMe: false
    }
    for (var key in (extras || {})) base[key] = extras[key]
    return base
  }

  function field(count, items, truncated) {
    return { count: count, items: items, truncated: truncated === true }
  }

  function payload() {
    return {
      ok: true,
      login: "yesheytenzin",
      orgs: ["acme-corp"],
      fetchedAt: 1791365239,
      scopes: {
        mine: {
          issues: field(3, [
            item("https://x/a", "2026-10-05T08:00:00Z", { number: 4, needsMe: true }),
            item("https://x/b", "2026-10-07T09:15:47Z", { number: 3 })
          ], true),
          prs: field(1, [
            item("https://x/c", "2026-08-03T04:57:25Z", { type: "pr", needsMe: true, draft: true, reviewDecision: "REVIEW_REQUIRED" })
          ], false)
        },
        orgs: {
          issues: field(4, [
            item("https://x/d", "2026-09-30T10:00:00Z", { scope: "orgs", needsMe: true })
          ], false),
          prs: field(1, [
            item("https://x/e", "2026-10-01T12:00:00Z", { type: "pr", scope: "orgs" })
          ], false)
        }
      }
    }
  }

  function parse(json) { return Model.parseRefresh(JSON.stringify(json)) }

  // ---- parsing ------------------------------------------------------------

  function testParseRefresh() {
    var parsed = parse(payload())
    expect(parsed !== null, "a real payload parses")
    expectEqual(parsed.login, "yesheytenzin", "login survives")
    expectEqual(parsed.scopes.mine.issues.items.length, 2, "items survive")
    expectEqual(parsed.scopes.mine.issues.items[0].updatedAtMs > 0, "true", "timestamps become numbers")
    expectEqual(parsed.scopes.mine.prs.items[0].draft, "true", "draft survives")
    expectEqual(parsed.scopes.orgs.prs.items[0].scope, "orgs", "org scope survives")

    // An item without a URL cannot be opened, so it is dropped rather than
    // rendered as a dead row.
    var withBadItem = { ok: true, scopes: { mine: { issues: field(1, [{ title: "no url" }], false), prs: field(0, [], false) },
                                            orgs: { issues: field(0, [], false), prs: field(0, [], false) } } }
    expectEqual(parse(withBadItem).scopes.mine.issues.items.length, 0, "an item without a url is dropped")

    // A count smaller than the list is a helper bug; the panel trusts the list.
    var lowCount = { ok: true, scopes: { mine: { issues: field(0, [item("https://x/a", "2026-10-05T08:00:00Z")], false),
                                              prs: field(0, [], false) },
                                         orgs: { issues: field(0, [], false), prs: field(0, [], false) } } }
    expectEqual(parse(lowCount).scopes.mine.issues.count, 1, "count never falls below the rows shown")

    // Leading junk (a mise/asdf banner on stdout) is tolerated.
    var noisy = JSON.stringify(payload())
    expect(Model.parseRefresh("shim banner\n" + noisy) !== null, "leading noise is tolerated")
  }

  function testRejects() {
    expect(Model.parseRefresh("") === null, "empty input is rejected")
    expect(Model.parseRefresh("nonsense") === null, "non-json is rejected")
    expect(Model.parseRefresh("{}") === null, "a payload without scopes is rejected")
    expect(Model.parseRefresh('{"scopes":{"mine":{}}}') === null, "a half payload is rejected")
    expect(Model.parseRefresh('{"ok":true,"login":"x"}') === null, "a success payload without scopes is rejected")
    expect(Model.parseRefresh('{"ok":false}') === null, "a failure payload without a type is rejected")

    // A typed failure is not a parse failure: the panel needs the kind and
    // the message so it can print the fix.
    var typed = Model.parseRefresh('{"ok":false,"error":"no-auth","message":"Run gh auth login"}')
    expect(typed !== null, "a typed failure parses")
    expectEqual(typed.ok, "false", "a typed failure is not ok")
    expectEqual(typed.error, "no-auth", "a typed failure keeps its kind")
    expectEqual(Model.errorNotice(typed.error, typed.message).hint.indexOf("gh auth login") !== -1, "true",
                "a typed failure still reaches the fix")
  }

  function testState() {
    expectEqual(Model.parseState("").scope, "mine", "an empty state defaults to personal")
    expectEqual(Model.parseState("garbage").tab, "issues", "a corrupt state defaults to issues")
    expectEqual(Model.parseState('{"scope":"all","tab":"prs"}').scope, "all", "a stored scope round-trips")
    expectEqual(Model.parseState('{"scope":"nope","tab":"nope"}').tab, "issues", "an unknown tab is clamped")
    expectEqual(Model.serializeState("all", "prs").indexOf('"scope": "all"') !== -1, "true", "state serializes")
    expectEqual(Model.serializeState("nope", "nope").indexOf('"tab": "issues"') !== -1, "true", "state serialization clamps")
  }

  function testCounts() {
    var scopes = parse(payload()).scopes
    var counts = Model.countsFor(scopes)
    expectEqual(counts.mine.issues, 3, "personal issue count")
    expectEqual(counts.mine.prs, 1, "personal PR count")
    expectEqual(counts.orgs.issues, 4, "org issue count")
    expectEqual(Model.badgeCount(scopes, "mine"), 4, "the bar badge counts personal items")
    expectEqual(Model.badgeCount(scopes, "all"), 9, "the bar badge counts orgs in")
    expectEqual(Model.attentionCount(scopes, "mine"), 2, "attention counts assigned and review-requested")
    expectEqual(Model.attentionCount(scopes, "all"), 3, "attention counts org items too")
    expectEqual(Model.badgeCount(Model.emptyScopes(), "all"), 0, "empty scopes count zero")
  }

  function testMerge() {
    var scopes = parse(payload()).scopes
    var all = Model.itemsFor(scopes, "all", "issues")
    expectEqual(all.length, 3, "org rows merge into the personal list")
    expectEqual(all[0].url, "https://x/b", "the merged list is newest first")
    expectEqual(all[2].url, "https://x/d", "the oldest row is last")
    expectEqual(Model.itemsFor(scopes, "mine", "issues")[0].url, "https://x/b", "the personal list stays personal")
    expectEqual(Model.itemsFor(scopes, "all", "prs")[0].url, "https://x/e", "PR rows merge too")

    // The same item can be reached by two searches; it must appear once.
    var duplicated = payload()
    duplicated.scopes.orgs.issues.items.push(item("https://x/b", "2026-10-07T09:15:47Z", { scope: "orgs" }))
    expectEqual(Model.itemsFor(parse(duplicated).scopes, "all", "issues").length, 3, "duplicate rows are collapsed")
  }

  function testStrings() {
    var scopes = parse(payload()).scopes
    contains(Model.updatedMeta(scopes, "mine", 0, false, 0), "3 issues", "the hero counts personal issues")
    contains(Model.updatedMeta(scopes, "all", 0, false, 0), "7 issues", "the hero counts org issues in")
    contains(Model.updatedMeta(scopes, "all", 0, false, 0), "2 pull requests", "the hero counts PRs")
    contains(Model.updatedMeta(scopes, "mine", 1791365239, false, 1791365239 * 1000 + 120000), "updated 2m ago", "the hero ages the refresh")
    contains(Model.updatedMeta(scopes, "mine", 1791365239, false, 1791365239 * 1000 + 5000), "updated just now", "a fresh refresh does not say 'now ago'")
    contains(Model.updatedMeta(scopes, "mine", 0, true, 0), "refreshing", "the hero says when it is fetching")

    expectEqual(Model.truncationHint(scopes, "all", "issues"), "Showing the most recent 3 of 7.", "truncation is explained")
    expectEqual(Model.truncationHint(scopes, "all", "prs"), "", "a complete list is not explained")
    expectEqual(Model.truncationHint(Model.emptyScopes(), "mine", "issues"), "", "empty scopes are not truncated")

    var now = 1791365239 * 1000
    expectEqual(Model.relativeTime(now, now), "now", "just now")
    expectEqual(Model.relativeTime(now - 300000, now), "5m", "minutes")
    expectEqual(Model.relativeTime(now - 10800000, now), "3h", "hours")
    expectEqual(Model.relativeTime(now - 172800000, now), "2d", "days")
    expectEqual(Model.relativeTime(now - 1814400000, now), "3w", "weeks")
    expectEqual(Model.relativeTime(0, now), "", "an unknown time is blank")
  }

  function testLabels() {
    expectEqual(Model.labelRgba("d73a4a", 0.95), "rgba(215,58,74,0.95)", "hex colors become rgba")
    expectEqual(Model.labelRgba("#00ff00", 1), "rgba(0,255,0,1)", "a leading hash is fine")
    expectEqual(Model.labelRgba("", 0.5), "rgba(128,128,128,0.5)", "a missing color falls back to grey")
    expectEqual(Model.labelRgba("zzzzzz", 0.5), "rgba(128,128,128,0.5)", "a broken color falls back to grey")
  }

  function testNotices() {
    contains(Model.errorNotice("no-gh", "").hint, "github-cli", "no-gh names the install command")
    contains(Model.errorNotice("no-auth", "").hint, "gh auth login", "no-auth names the fix")
    contains(Model.errorNotice("timeout", "").title, "did not answer", "timeout is explained")
    contains(Model.errorNotice("fetch-failed", "").hint, "retry", "fetch failures offer a retry")
    expectEqual(Model.errorNotice("mystery", "the helper exploded").title, "the helper exploded", "an unknown kind shows the message")
  }

  // ---- state chips --------------------------------------------------------

  function pr(extras) {
    var entry = item("https://x/pull", "2026-10-05T08:00:00Z", { type: "pr" })
    for (var key in (extras || {})) entry[key] = extras[key]
    return entry
  }

  function testChips() {
    // The flags the helper sends have to survive parsing first: a chip can
    // only say "assigned" if the row still knows it was.
    var parsed = parse({
      ok: true,
      scopes: {
        mine: {
          issues: field(1, [item("https://x/a", "2026-10-05T08:00:00Z", { assigned: true })], false),
          prs: field(1, [item("https://x/p", "2026-10-05T08:00:00Z", { type: "pr", assigned: true })], false)
        },
        orgs: { issues: field(0, [], false), prs: field(0, [], false) }
      }
    })
    expectEqual(parsed.scopes.mine.issues.items[0].assigned, "true", "an assignment survives parsing")
    expectEqual(parsed.scopes.mine.issues.items[0].needsMe, "true", "an assignment counts as yours")
    expectEqual(parsed.scopes.mine.prs.items[0].reviewRequested, "false", "a missing review flag stays false")

    // Pull request state.
    expectEqual(Model.stateChip(pr({ draft: true })).label, "DRAFT", "a draft says so")
    expectEqual(Model.stateChip(pr({ draft: true })).tone, "dim", "a draft is dim")
    expectEqual(Model.stateChip(pr({ reviewDecision: "APPROVED" })).tone, "success", "approved is success")
    expectEqual(Model.stateChip(pr({ reviewDecision: "CHANGES_REQUESTED" })).tone, "urgent", "changes requested is urgent")
    expectEqual(Model.stateChip(pr({ reviewDecision: "CHANGES_REQUESTED" })).label, "CHANGES REQUESTED", "changes requested reads in full")
    expectEqual(Model.stateChip(pr({ reviewDecision: "REVIEW_REQUIRED" })).tone, "warning", "needs review is a warning")
    expectEqual(Model.stateChip(pr({ reviewDecision: "REVIEW_REQUIRED" })).label, "NEEDS REVIEW", "needs review reads plainly")
    expectEqual(Model.stateChip(pr({})), null, "a pull request with no decision has no state chip")
    expectEqual(Model.stateChip(item("https://x/i", "2026-10-05T08:00:00Z")), null, "issues have no review state")

    // Why the row is yours.
    expectEqual(Model.youChip(item("https://x/i", "2026-10-05T08:00:00Z", { assigned: true })).label, "ASSIGNED", "an assigned row says so")
    expectEqual(Model.youChip(item("https://x/i", "2026-10-05T08:00:00Z", { assigned: true })).tone, "accent", "an assignment is accent")
    expectEqual(Model.youChip(pr({ reviewRequested: true })).tone, "urgent", "your review is urgent")
    expectEqual(Model.youChip(pr({ reviewRequested: true, assigned: true })).label, "YOUR REVIEW", "your review outranks assigned")
    expectEqual(Model.youChip(pr({})), null, "a row you only authored gets no chip")

    // The row tone drives the type glyph's colour.
    expectEqual(Model.rowTone(pr({ reviewDecision: "CHANGES_REQUESTED" })), "urgent", "changes requested colours the row")
    expectEqual(Model.rowTone(pr({ reviewDecision: "REVIEW_REQUIRED" })), "warning", "needs review colours the row")
    expectEqual(Model.rowTone(pr({ reviewDecision: "APPROVED" })), "success", "approved colours the row")
    expectEqual(Model.rowTone(pr({ draft: true })), "dim", "a draft stays dim")
    expectEqual(Model.rowTone(pr({ reviewRequested: true })), "urgent", "your review colours the row")
    expectEqual(Model.rowTone(item("https://x/i", "2026-10-05T08:00:00Z", { assigned: true })), "accent", "assigned is accent")
    expectEqual(Model.rowTone(item("https://x/i", "2026-10-05T08:00:00Z")), "dim", "a plain row takes no colour")
    expectEqual(Model.rowTone(pr({ reviewDecision: "APPROVED", reviewRequested: true })), "urgent", "your review outranks approved")
  }
}
