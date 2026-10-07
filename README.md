# GitHub Oma

Open issues and pull requests you are involved in, in the Omarchy bar — your
personal repos by default, one button away from your organizations, and a
third tab that browses the repos themselves.

```
󰊤 7        the bar: the GitHub mark, the count in the current scope,
           urgent when something is assigned to you or awaiting your review
```

Click it and the panel lists what needs you, newest first: each row is the
issue or pull request title with the repo it lives in underneath, and nothing
else. `Enter` opens one in the browser.

## What counts as "mine"

An item shows up when it is **open** and it **involves you** — you authored
it, you are assigned, you were mentioned, or your review was requested
(`involves:@me`). The scope decides which repos are searched, and the panel's
scope chips switch between all three:

| Chip | Scope | Repos searched |
|------|-------|----------------|
| `Personal · n` | `mine` | repos owned by your account (`user:<login>`) |
| `Orgs · n` | `orgs` | repos owned by organizations you can reach, one search per org |

Organizations are discovered from your memberships and from the orgs that own
repos you can see, so a private membership still shows up. `m` flips between
Personal and Orgs. The choice sticks: it lives in
`~/.local/state/omarchy/github-oma/state.json` and survives restarts.

## Repos

The `Repos · n` tab lists repositories, not items: one row per repo, the
`owner/name` alone, ordered starred first, then by the freshest push, then by
name. Clicking a row opens it.

The scope chips filter this list exactly as they filter issues and PRs:
`Personal` is the repos your account owns, `Orgs` the ones owned by your
organizations.

Organization repos come from a per-organization query sorted by push recency
and capped at 50 each: GitHub's gateway answers 502 on heavier repo queries.
When that cap bites, the panel says "showing the most recent 50 of 262" and
the chip still shows the true total.

## Requirements

The official GitHub CLI, installed and authenticated:

```sh
sudo pacman -S github-cli
gh auth login          # requests the repo and read:org scopes by default
```

`repo` and `read:org` are what let the panel see private and organization
repos. If `gh` is missing or signed out, the panel says so and names the
command instead of showing an empty list.

## Install

```sh
omarchy plugin add https://github.com/yesheytenzin/github-oma.git --enable
omarchy bar move tenzin.github-oma --section right
```

For development, drop the folder in place and let the shell reload it:

```sh
mkdir -p ~/.config/omarchy/plugins/tenzin.github-oma
cp -r ./* ~/.config/omarchy/plugins/tenzin.github-oma/
omarchy-shell shell rescanPlugins
omarchy plugin enable tenzin.github-oma
```

## Keys

| Key | Action |
|-----|--------|
| `j` / `k` | Move through the list (or the focused chip row) |
| `Tab` / `Shift+Tab` | Cycle the sections: tabs → scope → list |
| `1` / `2` / `3` | Issues / pull requests / repos |
| `m` | Flip the scope: Personal ⇄ Orgs |
| `Enter` / `o` | Open the selection in the browser |
| `g` / `G` | Jump to the top / bottom |
| `r` | Refresh now |
| `Esc` | Close the panel |

Mouse works too: click a row to open it, click a chip to switch, hover a row to
park the keyboard cursor there, middle-click the bar icon to refresh.

## Command line

```sh
omarchy-shell tenzin.github-oma toggle      # open/close the panel
omarchy-shell tenzin.github-oma open
omarchy-shell tenzin.github-oma close
omarchy-shell shell toggle tenzin.github-oma '{}'
```

Bind either to a hotkey and it behaves like a click on the bar icon.

## How it works

- `Service.qml` — the single poller. Fetches every 5 minutes, keeps the last
  good answer in `~/.local/state/omarchy/github-oma/cache.json`, and owns the
  scope/tab state. One poller for the whole shell, so a multi-monitor bar does
  not shell out once per screen.
- `BarWidget.qml` — the bar mark, the count, and the click target. Reads the
  service through the bar's scoped facade.
- `Panel.qml` — layout, the two chip rows, the list, and the keyboard cursor.
- `GithubModel.js` — the shaping: merging scopes, sorting, relative times,
  label colors, failure notices. Unit-tested headlessly.
- `bin/github-oma` — talks to GitHub through `gh api graphql`, one request per
  refresh with one search field per (scope, type). Retries transient gateway
  failures, types every failure for the panel, and never writes to GitHub.

Nothing in this plugin writes to GitHub: it reads, and it opens pages in your
browser.

## Troubleshooting

- **"GitHub CLI not found"** — install `github-cli`, then press `r`. The shell
  only sees the `PATH` it was started with; if `gh` lives in a shim directory
  (mise/asdf), put that directory on the PATH Hyprland launches the shell with
  and run `omarchy-restart-shell`.
- **"Not signed in to GitHub"** — `gh auth login`, then `r`.
- **An org or private repo is missing** — re-authenticate with the scopes:
  `gh auth refresh -s repo,read:org`.
- **"Could not reach GitHub"** — a transient GitHub failure; the helper already
  retried. Press `r`.
- **A long list says "showing the most recent N"** — GitHub's search returns at
  most 100 nodes per search; the count on the chip is still the true total.

## Tests

```sh
tests/run.sh                 # helper against a fake gh + the QML model headlessly
omarchy plugin validate .    # manifest and entry points
```

## Development

Saving `BarWidget.qml` or `Panel.qml` hot-reloads them inside the running
shell. `Service.qml` and `GithubModel.js` do not: the shell keeps the mounted
service instance and caches imported JS libraries, so apply those with

```sh
omarchy-restart-shell            # or: omarchy plugin disable/enable tenzin.github-oma
```

If a restart still shows an older panel, the shell is serving a compiled QML
artifact it considers current — `rm -rf ~/.cache/quickshell/qmlcache` and
restart again. Copying files in with preserved timestamps (rsync -a, tar -p)
is what usually triggers it.

## License

MIT — see [LICENSE](LICENSE).
