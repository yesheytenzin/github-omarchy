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
      testStrings()
      testScopes()
      testPrOrder()
      testRepos()
      testNotices()
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
          prs: field(3, [
            item("https://x/c", "2026-08-03T04:57:25Z", { type: "pr", authored: true }),
            item("https://x/f", "2026-08-20T10:00:00Z", { type: "pr", reviewRequested: true, needsMe: true }),
            item("https://x/g", "2026-08-25T10:00:00Z", { type: "pr" })
          ], false)
        },
        orgs: {
          issues: field(4, [
            item("https://x/d", "2026-09-30T10:00:00Z", { scope: "orgs", needsMe: true })
          ], true),
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
    expectEqual(Model.parseState('{"scope":"mine","tab":"prs"}').scope, "mine", "a stored scope round-trips")
    expectEqual(Model.parseState('{"scope":"nope","tab":"nope"}').tab, "issues", "an unknown tab is clamped")
    expectEqual(Model.serializeState("orgs", "prs").indexOf('"scope": "orgs"') !== -1, "true", "state serializes")
    expectEqual(Model.serializeState("nope", "nope").indexOf('"tab": "issues"') !== -1, "true", "state serialization clamps")
  }

  function testCounts() {
    var scopes = parse(payload()).scopes
    var counts = Model.countsFor(scopes)
    expectEqual(counts.mine.issues, 3, "personal issue count")
    expectEqual(counts.mine.prs, 3, "personal PR count")
    expectEqual(counts.orgs.issues, 4, "org issue count")
    expectEqual(Model.badgeCount(scopes, "mine"), 6, "the bar badge counts personal items")
    expectEqual(Model.attentionCount(scopes, "mine"), 2, "attention counts assigned and review-requested")
    expectEqual(Model.badgeCount(Model.emptyScopes(), "mine"), 0, "empty scopes count zero")
    expectEqual(Model.badgeCount(scopes, "orgs"), 5, "the org scope counts org items")
  }

  function testStrings() {
    var scopes = parse(payload()).scopes
    contains(Model.updatedMeta(scopes, "mine", 0, false, 0), "3 issues", "the hero counts personal issues")
    contains(Model.updatedMeta(scopes, "orgs", 0, false, 0), "4 issues", "the hero counts org issues")
    contains(Model.updatedMeta(scopes, "orgs", 0, false, 0), "1 pull request", "the hero counts org PRs")
    contains(Model.updatedMeta(scopes, "mine", 1791365239, false, 1791365239 * 1000 + 120000), "updated 2m ago", "the hero ages the refresh")
    contains(Model.updatedMeta(scopes, "mine", 1791365239, false, 1791365239 * 1000 + 5000), "updated just now", "a fresh refresh does not say 'now ago'")
    contains(Model.updatedMeta(scopes, "mine", 0, true, 0), "refreshing", "the hero says when it is fetching")

    expectEqual(Model.truncationHint(scopes, "mine", "issues"), "Showing the most recent 2 of 3.", "truncation is explained")
    expectEqual(Model.truncationHint(scopes, "mine", "prs"), "", "a complete list is not explained")
    expectEqual(Model.truncationHint(Model.emptyScopes(), "mine", "issues"), "", "empty scopes are not truncated")

    var now = 1791365239 * 1000
    expectEqual(Model.relativeTime(now, now), "now", "just now")
    expectEqual(Model.relativeTime(now - 300000, now), "5m", "minutes")
    expectEqual(Model.relativeTime(now - 10800000, now), "3h", "hours")
    expectEqual(Model.relativeTime(now - 172800000, now), "2d", "days")
    expectEqual(Model.relativeTime(now - 1814400000, now), "3w", "weeks")
    expectEqual(Model.relativeTime(0, now), "", "an unknown time is blank")
  }

  function testScopes() {
    var scopes = parse(payload()).scopes

    expectEqual(Model.clampScope("orgs"), "orgs", "orgs is a scope")
    expectEqual(Model.clampScope("nonsense"), "mine", "an unknown scope falls back to personal")
    expectEqual(Model.parseState('{"scope":"orgs"}').scope, "orgs", "an orgs scope round-trips")
    expect(Model.serializeState("orgs", "prs").indexOf('"scope": "orgs"') !== -1, "an orgs scope serializes")

    // Orgs-only shows org rows and nothing personal, and the counts follow.
    var orgItems = Model.itemsFor(scopes, "orgs", "issues")
    expectEqual(orgItems.length, 1, "orgs-only lists just the org rows")
    expectEqual(orgItems[0].url, "https://x/d", "the org row is the org issue")
    expectEqual(Model.itemsFor(scopes, "orgs", "issues")[0].scope, "orgs", "the org row is tagged as orgs")
    expectEqual(Model.itemsFor(scopes, "orgs", "prs").length, 1, "orgs-only lists org PRs too")

    expectEqual(Model.badgeCount(scopes, "orgs"), 5, "the orgs badge counts org items only")
    expectEqual(Model.badgeCount(scopes, "mine"), 6, "the personal badge stays personal")
    expectEqual(Model.attentionCount(scopes, "orgs"), 1, "attention follows the scope")

    contains(Model.updatedMeta(scopes, "orgs", 0, false, 0), "4 issues", "the orgs hero counts org issues")
    contains(Model.updatedMeta(scopes, "orgs", 0, false, 0), "1 pull request", "the orgs hero does not pluralize one")
    expectEqual(Model.updatedMeta(scopes, "orgs", 0, false, 0).indexOf("personal") !== -1, "false", "the orgs hero counts nothing personal")
    expectEqual(Model.truncationHint(scopes, "orgs", "issues"), "Showing the most recent 1 of 4.", "orgs truncation is explained")
    expectEqual(Model.truncationHint(Model.emptyScopes(), "orgs", "issues"), "", "an empty org scope is not truncated")
  }

  // ---- repos --------------------------------------------------------------

  function repoBucket(count, items, truncated) {
    return { count: count, truncated: truncated === true, items: items }
  }

  function reposField() {
    return {
      mine: repoBucket(2, [
        { kind: "repo", nameWithOwner: "yesheytenzin/job_application_portal", url: "https://x/p",
          pushedAt: "2026-08-03T04:57:25Z" },
        { kind: "repo", nameWithOwner: "yesheytenzin/auto-workspace", url: "https://x/a",
          pushedAt: "2026-10-07T09:15:47Z", starred: true }
      ]),
      orgs: repoBucket(30, [
        { kind: "repo", nameWithOwner: "acme-corp/widgets", url: "https://x/l",
          pushedAt: "2026-10-06T10:00:00Z" },
        { kind: "repo", nameWithOwner: "acme-corp/toolkit", url: "https://x/b",
          pushedAt: "2026-09-20T08:00:00Z" }
      ], true)
    }
  }

  function testRepos() {
    expectEqual(Model.clampTab("repos"), "repos", "repos is a tab")
    expectEqual(Model.parseState('{"tab":"repos"}').tab, "repos", "a repos tab round-trips")
    expect(Model.serializeState("mine", "repos").indexOf('"tab": "repos"') !== -1, "a repos tab serializes")

    // Built here rather than with Model.emptyScopes(): this payload is
    // JSON round-tripped, and a library-owned object does not survive it.
    var payload = parse({ ok: true,
      scopes: { mine: { issues: field(0, [], false), prs: field(0, [], false) },
                orgs: { issues: field(0, [], false), prs: field(0, [], false) } },
      repos: reposField() })
    expectEqual(payload.repos.mine.items.length, 2, "own repos survive parsing")
    expectEqual(payload.repos.orgs.count, 30, "the org bucket keeps its total")
    expectEqual(payload.repos.orgs.items[0].scope, "orgs", "the bucket stamps the row's scope")

    expectEqual(Model.reposFor(payload.repos, "mine").length, 2, "personal shows the repos you own")
    expectEqual(Model.reposFor(payload.repos, "orgs")[0].nameWithOwner, "acme-corp/widgets", "orgs shows org repos")

    var mine = Model.reposFor(payload.repos, "mine")
    expectEqual(mine[0].nameWithOwner, "yesheytenzin/auto-workspace", "the starred repo leads, however fresh the others are")
    expectEqual(mine[1].nameWithOwner, "yesheytenzin/job_application_portal", "the stalest personal repo is last")
    expectEqual(Model.reposFor(payload.repos, "orgs").length, 2, "orgs shows only org repos")

    expectEqual(Model.repoCountFor(payload.repos, "mine"), 2, "the personal chip counts owned repos")
    expectEqual(Model.repoCountFor(payload.repos, "orgs"), 30, "the orgs chip counts the whole org, not just the rows")
    expectEqual(Model.repoCountFor(Model.emptyRepoField(), "orgs"), 0, "an empty repo list counts zero")
    var countless = { mine: { count: 0, items: Model.reposFor(payload.repos, "mine") }, orgs: {} }
    expectEqual(Model.repoCountFor(countless, "mine"), 2, "a bucket without a total falls back to its rows")

    contains(Model.repoMeta(payload.repos, "orgs", 0, false, 0), "30 repos", "the repos hero counts the org bucket")
    contains(Model.repoMeta(payload.repos, "orgs", 0, true, 0), "refreshing", "the repos hero says when it is fetching")
    contains(Model.repoMeta(payload.repos, "orgs", 1791365239, false, 1791365239 * 1000 + 60000), "updated 1m ago", "the repos hero ages the refresh")

    expectEqual(Model.reposTruncationHint(payload.repos, "orgs"), "Showing the most recent 2 of 30.", "a capped org bucket is explained")
    expectEqual(Model.reposTruncationHint(payload.repos, "mine"), "", "a complete personal bucket is not explained")
  }

  // ---- pull request order -------------------------------------------------

  function testPrOrder() {
    var scopes = parse(payload()).scopes

    // Yours first, then the ones waiting on your review, then the rest — each
    // group newest first, so the undated-to-me PR cannot jump the queue.
    var prs = Model.itemsFor(scopes, "mine", "prs")
    expectEqual(prs.length, 3, "all three personal PRs are listed")
    expectEqual(prs[0].url, "https://x/c", "an authored PR leads even when it is the oldest")
    expectEqual(prs[1].url, "https://x/f", "a requested review comes second")
    expectEqual(prs[2].url, "https://x/g", "an involved-but-unasked PR comes last however fresh it is")

    // Issues keep plain recency: no groups there.
    var issues = Model.itemsFor(scopes, "mine", "issues")
    expectEqual(issues[0].url, "https://x/b", "issues stay newest first")
    expectEqual(issues[1].url, "https://x/a", "the older issue follows")

    // An authored PR that is also waiting on a review is still group one.
    var both = parse({ ok: true,
      scopes: { mine: { issues: field(0, [], false), prs: field(1, [item("https://x/h", "2026-08-01T00:00:00Z", { type: "pr", authored: true, reviewRequested: true, needsMe: true })], false) },
                orgs: { issues: field(0, [], false), prs: field(0, [], false) } } }).scopes
    expectEqual(Model.itemsFor(both, "mine", "prs")[0].url, "https://x/h", "your own PR outranks your own review request")
  }

  function testNotices() {
    contains(Model.errorNotice("no-gh", "").hint, "github-cli", "no-gh names the install command")
    contains(Model.errorNotice("no-auth", "").hint, "gh auth login", "no-auth names the fix")
    contains(Model.errorNotice("timeout", "").title, "did not answer", "timeout is explained")
    contains(Model.errorNotice("fetch-failed", "").hint, "retry", "fetch failures offer a retry")
    expectEqual(Model.errorNotice("mystery", "the helper exploded").title, "the helper exploded", "an unknown kind shows the message")
  }

}
