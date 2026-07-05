# News fragments

Instead of writing changelog entries by hand at release time (and getting merge
conflicts when several branches touch the same `CHANGELOG.md` lines), each
change that's worth mentioning adds its own small file here. `build-changelog.sh`
collects them into `CHANGELOG.md` at release time and deletes them.

## Adding a fragment

Create a file named:

```
<slug>.<type>.md
```

- `<slug>` — short, unique identifier for the change (an issue/PR number, or a
  short kebab-case name if there isn't one). Only used to keep filenames
  unique; it isn't shown in the changelog.
- `<type>` — one of:

  | type       | meaning                                  |
  |------------|-------------------------------------------|
  | `added`    | new feature or script                     |
  | `changed`  | behavior change to something existing     |
  | `fixed`    | bug fix                                   |
  | `removed`  | removed feature or file                   |
  | `security` | security-relevant fix                     |
  | `doc`      | documentation-only change                 |
  | `misc`     | anything else worth a line, no user impact|

The file's content is the changelog entry itself — one line (or a short
paragraph) of plain Markdown, written in the imperative/past tense the way a
changelog reads, e.g.:

```
$ cat newsfragments/42.added.md
Add `share-claude-config.sh` to symlink select config between profiles.
```

## Building the changelog

```bash
./build-changelog.sh <version>   # e.g. ./build-changelog.sh 1.1.0
```

This groups all fragments by type, prepends a dated section to
`CHANGELOG.md`, and deletes the consumed fragment files. Commit the result.

Fragments in this directory (other than this README) are things that haven't
shipped yet — if you're wondering what's changed since the last release, look
here as well as at `CHANGELOG.md`.
