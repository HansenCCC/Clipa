# Contributing to Clipa

Bug reports, focused fixes, documentation improvements, and translations are welcome.

For a bug report, include your macOS version, Clipa version, steps to reproduce,
and the expected behavior. Use synthetic clipboard examples. Never attach your
clipboard database, passwords, tokens, private documents, or unredacted logs.

## Development

Open `Clipa.xcodeproj` with Xcode 26 or later. Swift Package Manager resolves the
dependencies automatically. The checked-in project supports local ad-hoc signing;
you do not need the maintainer's Apple Developer account. See the README for the
command-line build.

After adding or removing source files, regenerate the project:

```sh
bundle install
bundle exec ruby gen_project.rb
```

Keep `Package.resolved` when regenerating so dependency versions stay pinned.
Run both regression harnesses before submitting a change to clipboard capture or
panel behavior:

```sh
zsh tests/run_clipboard_monitor_harness.sh
zsh tests/run_panel_controller_harness.sh
```

The panel harness opens temporary test panels and closes them on completion. It
does not launch the full application or read your clipboard history.

## Pull requests

Keep changes focused and explain the user-visible result and how you tested it.
Use the existing String Catalog for user-facing text and update the supported
translations together. Avoid unrelated formatting or generated project churn.

Contributions are submitted under the project's MIT license. Third-party code
must retain its own license and notices; see `THIRD_PARTY_NOTICES.md`.
