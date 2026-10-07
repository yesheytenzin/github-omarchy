# GitHub Oma

Open issues and pull requests you are involved in, in the Omarchy bar — your
personal repos by default, and one button away from your organizations too.

```
󰊤 7        the bar: the GitHub mark, the count in the current scope,
           urgent when something is assigned to you or awaiting your review
```

Click it and the panel lists what needs you, newest first: issue and PR titles,
`owner/repo#number`, labels, draft/review state, how long ago each last moved,
and a `→ you` marker on the rows that are actually waiting on you. `Enter`
opens one in the browser.

## What counts as "mine"

An item shows up when it is **open** and it **involves you** — you authored
it, you are assigned, you were mentioned, or your review was requested
(`involves:@me`). The scope decides which repos are searched:

| Scope | Repos searched |
|-------|----------------|
| `Personal` | repos owned by your account (`user:<login>`) |
| `+ Orgs · N` | personal repos **plus** every organization you can reach, one search per org |

Organizations are discovered from your memberships and from the orgs that own
repos you can see, so a private membership still shows up. The toggle sticks:
it lives in `~/.local/state/omarchy/github-oma/state.json` and survives
restarts.

## States and colours

Each row carries the state that decides what happens next, and why it is
yours, as tinted chips:

| Chip | Colour | Meaning |
|------|--------|---------|
| `APPROVED` | green | the pull request is approved |
| `CHANGES REQUESTED` | red | a reviewer asked for changes |
| `NEEDS REVIEW` | yellow | waiting on a review before it can move |
| `DRAFT` | grey | still a draft |
| `YOUR REVIEW` | red | your review is the one being waited on |
| `ASSIGNED` | accent | assigned to you |

The issue/PR glyph at the left of every row takes the colour of its worst
state, so one scan down that column reads the whole list; the row itself is
also tinted while the keyboard cursor is on it. Green and yellow are picked
for the active theme's light or dark background, since the shell has no
token for either; red, grey, and the accent come from the theme.

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
| `1` / `2` | Issues / pull requests |
| `m` | Toggle organizations on and off |
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

## License

MIT — see [LICENSE](LICENSE).
