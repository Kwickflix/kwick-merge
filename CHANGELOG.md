# Changelog

All notable changes to Kwick_Merge are recorded here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

Nothing yet.

---

## [1.1.0] — 2026-07-16

Metadata release. 1.0.0 merged the audio perfectly and quietly threw away half
of what made the book usable.

### Added

- **Chapter stitching** — every chapter from every file now survives the merge.
  Each input is probed for its chapters, and each chapter's start/end is shifted
  by the running total of the files before it, so they land on the merged
  timeline where they belong. A two-part book with 39 + 29 chapters comes out
  with all 68, in order.
- **Chapters for files that have none** — each file becomes one chapter named
  after itself, so a folder of `Track 01.mp3` … `Track 12.mp3` merges into
  something you can still skip through.
- **Cover art is kept** — the artwork on the first file is carried over and
  re-attached as proper embedded cover art.
- **Tags are kept** — artist, album, year and the rest come across from the first
  file. The **title** is deliberately overridden with your output name, so a
  merged book is no longer titled "…: Part One" while containing the whole thing.
- **Pre-merge summary** now reports the chapter count and whether cover art was
  found, before you commit to the merge.
- **Opens as a tab, not a new window** — if a Windows Terminal window is already
  open, the launcher drops the merge into it as a new tab (`wt -w 0 new-tab`);
  only a cold start opens a fresh, banner-sized window.
- **Closing the window really stops the merge** — FFmpeg is now bound to the
  script by a Windows Job Object marked kill-on-close, so the X button, Task
  Manager, or a crash takes FFmpeg down with it instead of leaving it encoding
  forever into a file nobody will finish.
- **Abandoned temp files are swept on startup** — a leftover `.merging` file from
  an interrupted run is cleaned up when you next run the tool on that folder.

### Fixed

- **Chapters were silently half-lost.** Left alone, FFmpeg copies chapters from
  the *first* input only — so 1.0.0 produced files with part one's chapters and
  **nothing at all** for the rest of the book, which is arguably worse than no
  chapters, since the list looks complete until you reach the middle. Verified on
  a real two-part book: 39 chapters kept, 29 silently dropped.
- **Merged books inherited the first part's title**, e.g. a complete book titled
  "Binding 13: Part One".
- **Cover art was dropped**, because only the audio stream was mapped.
- **Cover art made the merge hang at 0% for over ten minutes.** Audiobook cover
  tracks are flagged `attached_pic` but carry the full runtime as their duration
  (57,000+ seconds), and mapping that stream straight out of the book made FFmpeg
  chew through the entire input before writing a byte. The cover is now extracted
  to a small temp image first (~0.2s) and attached as its own input, so progress
  starts within a second. This was the single worst regression of the release.
- **Progress bar left ghost copies of itself** as it climbed. The block remembered
  an absolute row and reused it; every time the window scrolled, that row drifted
  and the redraw orphaned the old bar. It now moves the cursor relative to its live
  position each redraw, so scrolling can't desync it — verified to stay a single
  block across 21 redraws forced to the bottom of the window.
- **README was wrong about chapters** — it claimed they simply weren't carried
  across. They were, just badly. Documented properly now.

### Notes for anyone reading the source

- The chapter metadata file must be written as UTF-8 **without a BOM**. FFmpeg
  rejects a BOM'd ffmetadata file outright with "Invalid data found when
  processing input". PowerShell's `Set-Content -Encoding UTF8` writes one, hence
  the explicit `UTF8Encoding($false)`.
- Never map an audiobook's cover stream directly (`-map 0:v:0`) — extract the
  frame first. See the cover-hang fix above.
- The kill-on-close behaviour uses a `CreateJobObject` +
  `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` P/Invoke; FFmpeg is assigned to the job
  right after it starts.

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

[Unreleased]: https://github.com/Kwickflix/kwick-merge/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Kwickflix/kwick-merge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Kwickflix/kwick-merge/releases/tag/v1.0.0
