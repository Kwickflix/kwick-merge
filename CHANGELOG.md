# Changelog

All notable changes to Kwick_Merge are recorded here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

Nothing yet.

---

## [1.0.0] — 2026-07-16

First public release. The tool has been in private use for a while; this is the
point where it became safe and pleasant enough to hand to someone else.

### Added

- **Drag-and-drop merging** — drop a folder on `kwick-merge.cmd` and every
  `.mp3` / `.m4a` / `.m4b` inside is joined into one file, in the same format.
- **Natural sort ordering** — numbers are zero-padded before sorting, so
  `Part 2` comes before `Part 10` instead of after it.
- **Output name prompt** — defaults to the folder name; type your own or press
  `Enter`. Illegal Windows characters are stripped and reported. A typed
  extension is ignored rather than doubled up.
- **Keep-or-delete prompt** — `[K]` keeps the source parts (default), `[D]`
  sends them to the **Recycle Bin**, and only ever after a successful merge.
- **Cancel key** — `Q` or `Esc` during the merge stops FFmpeg, removes the
  part-finished temp file, and leaves the folder untouched.
- **Live progress block** — percentage, progress bar, elapsed time, and an ETA
  calculated from real throughput, redrawn in place.
- **Automatic format matching** — MP3 in, MP3 out (`libmp3lame -q:a 2`);
  M4A/M4B in, AAC out (`96k`). Mixed-type folders are refused rather than
  guessed at.
- **Filename hygiene pass** — files containing characters Windows can't handle
  are renamed before the merge starts, so FFmpeg never fails halfway through.
- **Error log** — a `.merge-log.txt` is written next to the output with FFmpeg's
  own output whenever anything goes wrong.
- **Banner** — KWICKFLIX.SHOP block-art logo with a green→silver→blue gradient,
  clickable in Windows Terminal, plus a compact logo that's used automatically
  when the window is too narrow for the full one.
- **Right-sized window** — the launcher opens Windows Terminal at 150×40 at the
  top-left, so the banner always fits and the window never lands off-screen.

### Safety

- **Temp-file merging** — the merge writes to `<name>.merging.<ext>` and is only
  renamed into place once FFmpeg exits cleanly. A crash, a cancel or a power cut
  can't leave you with a broken file where your book used to be.
- **Name-collision handling** — when the output name matches one of the source
  files (a folder called `Part 1` holding `Part 1.m4b`), that file is still used
  as an input and is only recycled and replaced after the new file exists. The
  script warns you before starting.
- **Deletion is opt-in, recoverable, and success-gated** — sources go to the
  Recycle Bin, never a hard delete, and never unless the merge worked.

### Fixed

These were all found and fixed during the run-up to this release:

- **Merge froze at 0% and ignored the cancel key.** Pressing `[Y]` to start left
  a key-*up* event in the input buffer. The cancel check saw "a key is available"
  and called `ReadKey` in a mode that only accepts key-*downs*, so it blocked
  forever waiting for a keypress that could never arrive. FFmpeg's output pipe
  filled up behind the stalled reader and everything stopped. The check now
  accepts and discards key-up events, and the input buffer is flushed after the
  start prompt.
- **Progress block printed a new copy on every update** instead of redrawing in
  place. The block ended with a newline, which scrolls the window when drawn at
  the bottom row, leaving the saved row pointing at the wrong line. The trailing
  newline is gone and the block re-anchors itself after each redraw.
- **Durations over 24 hours displayed wrong.** A 25 h 51 m book showed as
  `01:51:48` — the hours field rolled over at a day. Fixed by formatting from
  total hours; then fixed again, because `[int]25.86` *rounds* to 26 in
  PowerShell rather than truncating. It floors now.
- **A source file sharing the output's name was silently dropped**, which could
  turn a two-file folder into "Need at least 2 source audio files". See
  *Name-collision handling* above.
- **Leftover `.merging` temp files were treated as source audio** on a later run.
  They're excluded from discovery now.
- **A chatty FFmpeg could deadlock the script** — its error pipe was left unread
  until after exit, so filling the 4 KB buffer would block it forever. The error
  stream is now drained in the background.

[Unreleased]: https://github.com/Kwickflix/kwick-merge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Kwickflix/kwick-merge/releases/tag/v1.0.0
