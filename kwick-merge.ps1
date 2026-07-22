param(
    [string]$Folder
)

<#
Kwick_Merge 1.1.0
https://github.com/Kwickflix/kwick-merge

Merges the MP3/M4A/M4B files in a folder into one file. PowerShell 5.1 safe.

• Drag-drop folder support via -Folder
• Natural sort, so "Part 2" comes before "Part 10"
• No concat list - each file is a direct FFmpeg input
• Output name = folder name, or type your own at the prompt
• Auto output type = MP3, M4A, or M4B (based on inputs)
• Chapters from EVERY file, shifted onto the merged timeline (see the
  ffmetadata block below - FFmpeg alone would keep only the first file's)
• Cover art and tags carried over; title set to the output name
• Live progress: %, bar, elapsed, ETA. [Q] cancels mid-merge
• Optionally deletes the source files (Recycle Bin) after a successful merge
• Merges to a temp file, renamed at the end, so nothing is lost on failure
• On ANY error: writes a log next to where the output would be
• Always pauses at end (ENTER or SPACE)

NOTE: keep this file saved as UTF-8 WITH BOM or the banner art turns to mojibake.
#>

$ffmpeg  = "ffmpeg"
$ffprobe = "ffprobe"

# Colour roles, so the whole UI stays consistent
$cHead = "Cyan"        # section headings
$cVal  = "Green"       # chosen values / good news
$cName = "Yellow"      # names and numbers worth reading
$cBad  = "Red"         # destructive or failed
$cDim  = "DarkGray"    # instructions and chrome
$cTxt  = "Gray"        # ordinary text

try { $Host.UI.RawUI.WindowTitle = "Kwick_Merge" } catch {}

# The banner art uses block characters, so the console must be in UTF-8.
# This file must stay saved as UTF-8 WITH BOM or PowerShell 5.1 mangles them.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$adUrl = "https://www.Kwickflix.shop"

$adArtWide = @'
 ┌───┐ ┌─┐ ┌──┐  ┌─┐ ┌───────┐ ┌───────┐ ┌───┐ ┌─┐ ┌───────┐ ┌───┐     ┌───────┐ ┌───┐ ┌─┐           ┌───────┐ ┌───┐ ┌─┐ ┌───────┐ ┌───────┐
═│∙  │═│∙│═│∙ │══│∙│═╘═╕∙  ╒═╛═│∙  ╒═╕∙│═│∙  │═│∙│═│∙  ╒═╕∙│═│∙  │═════╘═╕∙  ╒═╛═│∙  │═│∙│═══════════│∙╒═════╛═│∙  │═│∙│═│∙  ╒═╕∙│═│∙  ╒═╕∙│
 │   └─┘┌┘░│  │▓█│ │ ▓▓│   │░▓ │   │▓└─┘ │   └─┘┌┘ │   └┐└─┘░│   │█▓▓▓ ▓▓│   │░▓ ╘╕  └─┘╒╛░█░░▒▒░█░▓▓│ └─────┐ │   └─┘ │░│   │█│ │ │   └─┘ │
░│   ╒═╕└┐▒│  │╒╕│ │░░░│   │▓█░│   │░┌─┐░│   ╒═╕└┐░│   ┌┘░▒▓▒│   │▓┌─┐░░░│   │▓█░┌┘  ╒═╕└┐▓▒░▒█▓▒░▓██╘═══╕  ∙│░│   ╒═╕ │▒│   │▓│ │░│   ╒═══╛
▒│   │░│ │▓│  └┘└┘ │▒▒▒│   │░▒▒│   │░│ │▒│   │░│ │▒│   │░░▒▓▓│   └─┘ │▒▒▒│   │░▒▒│   │░│ │▒▒░░░▒░░░▒▓┌───┘   │▒│   │░│ │▓│   └─┘ │▒│   │░░▒▓
═│∙  │═│∙│═│∙     ∙│═┌─┘∙  └─┐═│∙  ╘═╛∙│═│∙  │═│∙│═│∙  │═════│∙     ∙│═┌─┘∙  └─┐═│∙  │═│∙│══┌───┐════│∙     ∙│═│∙  │═│∙│═│∙     ∙│═│∙  │════
 ╘═══╛ ╘═╛ ╘═══════╛ ╘═══════╛ ╘═══════╛ ╘═══╛ ╘═╛ ╘═══╛     ╘═══════╛ ╘═══════╛ ╘═══╛ ╘═╛  ╘═══╛    ╘═══════╛ ╘═══╛ ╘═╛ ╘═══════╛ ╘═══╛
'@

# Used when the window is too narrow for the big one (it would wrap and look broken)
$adArtSmall = @'
█  █ █   █ ███  ███ █  █ ████ █    ███ █   █    ███ █  █  ██  ███
█ █  █   █  █  █    █ █  █    █     █   █ █    █    █  █ █  █ █  █
██   █ █ █  █  █    ██   ███  █     █    █      ██  ████ █  █ ███
█ █  ██ ██  █  █    █ █  █    █     █   █ █       █ █  █ █  █ █
█  █ █   █ ███  ███ █  █ █    ████ ███ █   █ █ ███  █  █  ██  █
'@

# Top-to-bottom gradient stops: green -> silver -> blue
$adStops = @(
    @(90,220,120),
    @(200,210,215),
    @(70,90,240)
)

function Get-AdColor([int]$i, [int]$n) {
    if ($n -le 1) { return $adStops[0] }

    # Position across the stops, then blend between the two nearest
    $t = ($i / ($n - 1)) * ($adStops.Count - 1)
    $a = [int][math]::Floor($t)
    $b = [math]::Min($a + 1, $adStops.Count - 1)
    $f = $t - $a

    return @(0, 1, 2 | ForEach-Object {
        [int]($adStops[$a][$_] + (($adStops[$b][$_] - $adStops[$a][$_]) * $f))
    })
}

function Get-ArtWidth([string]$art) {
    ($art -split "`r?`n" | Measure-Object -Property Length -Maximum).Maximum
}

function Try-WidenWindow([int]$want) {
    # Best effort only - Windows Terminal ignores this, plain consoles honour it.
    try {
        $rui = $Host.UI.RawUI
        if ($rui.WindowSize.Width -ge $want) { return }

        $max = $rui.MaxWindowSize.Width
        $target = [math]::Min($want, $max)

        $buf = $rui.BufferSize
        if ($buf.Width -lt $target) { $buf.Width = $target; $rui.BufferSize = $buf }

        $win = $rui.WindowSize
        $win.Width = $target
        $rui.WindowSize = $win
    } catch { }
}

function Write-Ad {
    $e = [char]27

    # Pick the biggest logo that fits, so it never wraps
    $wide = Get-ArtWidth $adArtWide
    Try-WidenWindow ($wide + 2)

    $cols = 120
    try { $cols = $Host.UI.RawUI.WindowSize.Width } catch { }

    $adArt = if ($cols -ge $wide) { $adArtWide } else { $adArtSmall }
    $lines = $adArt -split "`r?`n"

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($env:WT_SESSION) {
            $c = Get-AdColor $i $lines.Count
            # Colour + its own hyperlink, so the whole banner is clickable.
            Write-Host ("{0}[38;2;{1};{2};{3}m{0}]8;;{4}{0}\{5}{0}]8;;{0}\{0}[0m" -f `
                $e, $c[0], $c[1], $c[2], $adUrl, $line)
        } else {
            # 16-colour consoles get a rough three-band approximation
            if ($i -lt $lines.Count / 3)          { $basic = "Green" }
            elseif ($i -lt $lines.Count * 2 / 3)  { $basic = "Gray"  }
            else                                  { $basic = "Blue"  }
            Write-Host $line -ForegroundColor $basic
        }
    }
}

Write-Host ""
Write-Host ""
Write-Ad
Write-Host ""
Write-Host "=== KWICK_MERGE ===" -ForegroundColor $cHead
Write-Host "=== MP3 / M4A / M4B ===" -ForegroundColor $cDim
Write-Host ""

# ---------------- LOGGING ----------------
$logLines = New-Object System.Collections.Generic.List[string]

function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    $logLines.Add($line) | Out-Null
}

function Flush-Log([string]$path) {
    try { $logLines | Out-File -FilePath $path -Encoding UTF8 }
    catch {
        Write-Host "ERROR: Failed to write log: $path"
        Write-Host $_.Exception.Message
    }
}

function Fail([string]$msg, [int]$code = 1) {
    if (-not $script:logPath) {
        $base = $PWD.Path
        if ($script:folder -and (Test-Path -LiteralPath $script:folder -PathType Container)) { $base = $script:folder }

        $safe = "merge"
        try {
            $safe = Split-Path -Leaf $base
            $safe = ($safe -replace '[<>:"/\\|?*\x00-\x1F]', '').Trim().TrimEnd('.', ' ')
            if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "merge" }
        } catch { $safe = "merge" }

        $script:logPath = Join-Path $base ($safe + ".merge-log.txt")
    }

    Log ("ERROR: " + $msg)
    Flush-Log $script:logPath

    Write-Host ""
    Write-Host "ERROR: $msg"
    Write-Host ""
    Write-Host "Log written:"
    Write-Host " - $($script:logPath)"
    Write-Host ""
    Write-Host "Press [Enter] or [Space] to close..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit $code
}

function Wait-ForStart {
    Write-Host ""
    Write-Host "Press " -NoNewline -ForegroundColor $cDim
    Write-Host "[Y]" -NoNewline -ForegroundColor $cVal
    Write-Host " or " -NoNewline -ForegroundColor $cDim
    Write-Host "[Space]" -NoNewline -ForegroundColor $cVal
    Write-Host " to start, any other key to cancel..." -ForegroundColor $cDim

    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    if ($key.Character -eq 'Y' -or
        $key.Character -eq 'y' -or
        $key.VirtualKeyCode -eq 32) {
        Write-Host "Starting merge..." -ForegroundColor $cVal
        # Drop the key-up event this keypress leaves behind, so the cancel
        # check during the merge starts from a clean input buffer.
        try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
        return
    }

    Write-Host ""
    Write-Host "Cancelled by user." -ForegroundColor $cName
    Write-Host "Press [Enter] or [Space] to close..." -ForegroundColor $cDim
    $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

function Wait-ToClose {
    Write-Host ""
    Write-Host "Press [Enter] or [Space] to close..." -ForegroundColor $cDim
    while ($true) {
        $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($k.VirtualKeyCode -eq 13 -or $k.VirtualKeyCode -eq 32) { break }
    }
}

function Remove-ToRecycleBin([string]$path) {
    # Recycle Bin rather than a hard delete, so a replaced source file is recoverable.
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        Write-Host " - Recycle Bin: " -NoNewline -ForegroundColor $cDim
        Write-Host (Split-Path -Leaf $path) -ForegroundColor $cTxt
        Log "Recycled: $path"
    } catch {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        Write-Host " - Deleted: " -NoNewline -ForegroundColor $cBad
        Write-Host (Split-Path -Leaf $path) -ForegroundColor $cTxt
        Log ("Deleted (Recycle Bin unavailable): " + $path)
    }
}

function Get-SafeFileName([string]$name) {
    $clean = ($name -replace '[<>:"/\\|?*\x00-\x1F]', '') -replace '\s{2,}', ' '
    $clean = $clean.Trim().TrimEnd('.', ' ')
    return $clean
}

function Escape-Meta([string]$s) {
    # ffmetadata treats = ; # and \ as special, and a newline would end the value
    if ($null -eq $s) { return "" }
    $e = $s -replace '([=;#\\])', '\$1'
    return ($e -replace "`r?`n", ' ')
}

function Ask-OutputName([string]$autoName, [string]$ext) {
    Write-Host ""
    Write-Host "Output name:" -ForegroundColor $cHead
    Write-Host "  Automatic name is " -NoNewline -ForegroundColor $cDim
    Write-Host "$autoName$ext" -ForegroundColor $cName
    Write-Host "  Press [Enter] to use it, or type a different name." -ForegroundColor $cDim
    Write-Host ""
    Write-Host "  Name: " -NoNewline -ForegroundColor $cHead

    # Tint what the user types, then put the console back how we found it
    $prev = $null
    try { $prev = $Host.UI.RawUI.ForegroundColor; $Host.UI.RawUI.ForegroundColor = $cVal } catch { }
    $answer = Read-Host
    if ($null -ne $prev) { try { $Host.UI.RawUI.ForegroundColor = $prev } catch { } }

    if ([string]::IsNullOrWhiteSpace($answer)) {
        Write-Host "  Using: " -NoNewline -ForegroundColor $cDim
        Write-Host "$autoName$ext" -ForegroundColor $cVal
        return $autoName
    }

    # Ignore an extension if they typed one
    if ($answer.ToLowerInvariant().EndsWith($ext)) {
        $answer = $answer.Substring(0, $answer.Length - $ext.Length)
    }

    $clean = Get-SafeFileName $answer
    if ([string]::IsNullOrWhiteSpace($clean)) {
        Write-Host "  That name cannot be used. Falling back to the automatic name." -ForegroundColor $cBad
        return $autoName
    }

    if ($clean -ne $answer.Trim()) {
        Write-Host "  Name cleaned up to: " -NoNewline -ForegroundColor $cDim
        Write-Host "$clean$ext" -ForegroundColor $cName
    }
    return $clean
}

function Ask-DeleteSources {
    Write-Host ""
    Write-Host "After a successful merge:" -ForegroundColor $cHead
    Write-Host "  [K]" -NoNewline -ForegroundColor $cVal
    Write-Host " Keep the source files      (default)" -ForegroundColor $cTxt
    Write-Host "  [D]" -NoNewline -ForegroundColor $cBad
    Write-Host " Delete the source files    (sent to the Recycle Bin)" -ForegroundColor $cTxt
    Write-Host ""
    Write-Host "  Press [K] or [D]..." -ForegroundColor $cDim

    while ($true) {
        $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $c = "$($k.Character)".ToLowerInvariant()

        if ($c -eq 'k' -or $k.VirtualKeyCode -eq 13) {
            Write-Host "  Selection: " -NoNewline -ForegroundColor $cHead
            Write-Host "[K]" -NoNewline -ForegroundColor $cVal
            Write-Host " keep the source files" -ForegroundColor $cTxt
            return $false
        }
        if ($c -eq 'd') {
            Write-Host "  Selection: " -NoNewline -ForegroundColor $cHead
            Write-Host "[D]" -NoNewline -ForegroundColor $cBad
            Write-Host " delete the source files" -ForegroundColor $cTxt
            return $true
        }
    }
}

# -----------------------------------------

# Decide target folder
if ([string]::IsNullOrWhiteSpace($Folder)) {
    $folder = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $folder = $Folder
}

# If user dragged a file by accident, normalize to its parent
if (Test-Path -LiteralPath $folder -PathType Leaf) {
    $folder = Split-Path -Parent $folder
}

# Validate folder exists
if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
    Write-Host "ERROR: Folder not found: $folder"
    Write-Host "Press [Enter] or [Space] to close..."
    $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

$script:folder = $folder
Set-Location -LiteralPath $folder

# Sweep up temp files abandoned by an earlier run (window closed mid-merge, power
# cut, etc). A finished merge never leaves one behind, so any we find are junk.
Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
    Where-Object { $_.BaseName -like "*.merging" -and $_.Extension -in ".mp3", ".m4a", ".m4b" } |
    ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            Write-Host "Cleaned up an abandoned part-file: " -NoNewline -ForegroundColor $cDim
            Write-Host $_.Name -ForegroundColor $cTxt
        } catch {
            # Still locked - another merge is probably running on this folder
            Write-Host "Note: '$($_.Name)' is in use - is another merge running?" -ForegroundColor $cName
        }
    }

# Get MP3/M4A/M4B
$files = Get-ChildItem -LiteralPath $folder -File | Where-Object {
    $_.Extension -in ".mp3", ".m4a", ".m4b" -and $_.BaseName -notlike "*.merging"
}

# Auto-fix bad filenames before anything else
foreach ($f in $files) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $extName  = $f.Extension
    $cleanBaseName = Get-SafeFileName $baseName
    $cleanName = $cleanBaseName + $extName

    if ([string]::IsNullOrWhiteSpace($cleanBaseName)) {
        Fail "A file would become blank after cleaning: $($f.Name)"
    }

    if ($cleanName -ne $f.Name) {
        $targetPath = Join-Path $folder $cleanName

        if ((Test-Path -LiteralPath $targetPath) -and ($targetPath -ne $f.FullName)) {
            Fail "Cannot rename '$($f.Name)' because '$cleanName' already exists"
        }

        try {
            Rename-Item -LiteralPath $f.FullName -NewName $cleanName -ErrorAction Stop
            Write-Host "Renamed: $($f.Name) -> $cleanName"
            Log "Renamed: $($f.Name) -> $cleanName"
        } catch {
            Fail ("Failed to rename file: " + $f.Name + " | " + $_.Exception.Message)
        }
    }
}

# Reload after rename
$files = Get-ChildItem -LiteralPath $folder -File | Where-Object {
    $_.Extension -in ".mp3", ".m4a", ".m4b" -and $_.BaseName -notlike "*.merging"
}

if ($files.Count -lt 2) { Fail "Need at least 2 audio files (.mp3, .m4a, or .m4b)" }

# Natural sort - this is the order they get joined in
$files = $files | Sort-Object {
    [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(10,'0') })
}

# Determine extensions robustly
$exts = @($files | ForEach-Object { $_.Extension.ToLowerInvariant() } | Select-Object -Unique)

if ($exts.Count -ne 1) {
    Fail ("Mixed file types detected. Detected: " + ($exts -join ", "))
}

$ext = [string]$exts[0]
if ([string]::IsNullOrWhiteSpace($ext) -or ($ext -ne ".mp3" -and $ext -ne ".m4a" -and $ext -ne ".m4b")) {
    Fail ("Could not determine output type. Detected: " + ($exts -join ", "))
}

# Automatic output filename = folder name
$autoName = Split-Path -Leaf $folder
$autoName = ($autoName -replace '[<>:"/\\|?*\x00-\x1F]', '').Trim().TrimEnd('.', ' ')
if ([string]::IsNullOrWhiteSpace($autoName)) { $autoName = "merged" }

Write-Host "Folder:" -ForegroundColor $cHead
Write-Host " - $folder" -ForegroundColor $cTxt
Write-Host ""
Write-Host "Files detected " -NoNewline -ForegroundColor $cHead
Write-Host "($ext):" -ForegroundColor $cName
$files | ForEach-Object {
    Write-Host " - " -NoNewline -ForegroundColor $cDim
    Write-Host $_.Name -ForegroundColor $cTxt
}

$bookName = Ask-OutputName $autoName $ext
$deleteSources = Ask-DeleteSources

$outFile = Join-Path $folder ($bookName + $ext)
$tempOut = Join-Path $folder ($bookName + ".merging" + $ext)
$logPath = Join-Path $folder ($bookName + ".merge-log.txt")
$script:logPath = $logPath

if ($outFile -match '\.$') {
    Fail ("Output filename ended with a dot (invalid on Windows). Output: " + $outFile)
}

# The merge writes to $tempOut and is renamed at the very end, so a source file
# that already has the output's name can still be used as an input.
$outIsSource = [bool]($files | Where-Object { $_.FullName -eq $outFile })

Write-Host ""
Write-Host "-----------------------------------" -ForegroundColor $cDim
Write-Host "Output will be:" -ForegroundColor $cHead
Write-Host " - " -NoNewline -ForegroundColor $cDim
Write-Host (Split-Path -Leaf $outFile) -ForegroundColor $cVal
Write-Host ""
Write-Host "Source files: " -NoNewline -ForegroundColor $cHead
if ($deleteSources) {
    Write-Host "DELETE after merge (Recycle Bin)" -ForegroundColor $cBad
} else {
    Write-Host "keep" -ForegroundColor $cVal
}
Write-Host "-----------------------------------" -ForegroundColor $cDim
Write-Host ""

if ($outIsSource) {
    Write-Host "NOTE: '$(Split-Path -Leaf $outFile)' is also one of the source files." -ForegroundColor $cName
    Write-Host "      It will be used as an input, then sent to the Recycle Bin and" -ForegroundColor $cName
    Write-Host "      replaced by the merged file - only if the merge succeeds." -ForegroundColor $cName
    Write-Host ""
    Log "Output name matches a source file; it will be replaced after a successful merge."
}

Log "Folder: $folder"
Log "Detected type: $ext"
Log "Output: $outFile"
Log ("Delete sources after merge: " + $deleteSources)

# Probe every input once - duration AND chapters in a single call
Write-Host "Reading chapters..." -ForegroundColor $cDim

$totalSec = 0.0
$probes   = @()

foreach ($f in $files) {
    $info = $null
    try {
        $raw  = & $ffprobe -v error -show_chapters -show_entries format=duration -of json -- "$($f.FullName)" 2>$null
        $info = ($raw -join "`n") | ConvertFrom-Json
    } catch { }

    $dur = 0.0
    if ($info -and $info.format -and $info.format.duration) {
        try { $dur = [double]$info.format.duration } catch { $dur = 0.0 }
    }

    $chaps = @()
    if ($info -and $info.chapters) { $chaps = @($info.chapters) }

    $probes   += [pscustomobject]@{ File = $f; Duration = $dur; Chapters = $chaps }
    $totalSec += $dur
}

if ($totalSec -le 0) { $totalSec = 1.0 }

# One metadata file holds the book's tags and every chapter shifted onto the
# merged timeline. Without it FFmpeg copies chapters from the FIRST input only,
# so a two-part book keeps part one's chapters and the rest gets none.
$metaLines = New-Object System.Collections.Generic.List[string]
$metaLines.Add(";FFMETADATA1")

# Keep the first file's tags (artist, album, year...) but retitle the output,
# or a merged book stays titled "...: Part One".
try {
    $tagRaw = & $ffprobe -v error -show_entries format_tags -of json -- "$($files[0].FullName)" 2>$null
    $tagObj = ($tagRaw -join "`n") | ConvertFrom-Json
    if ($tagObj -and $tagObj.format -and $tagObj.format.tags) {
        foreach ($p in $tagObj.format.tags.PSObject.Properties) {
            if ($p.Name -ieq 'title') { continue }
            if ($null -eq $p.Value -or "$($p.Value)".Trim().Length -eq 0) { continue }
            $metaLines.Add((Escape-Meta $p.Name) + "=" + (Escape-Meta "$($p.Value)"))
        }
    }
} catch { }

$metaLines.Add("title=" + (Escape-Meta $bookName))

$chapterCount = 0
$offsetMs     = 0.0

foreach ($p in $probes) {
    if ($p.Chapters.Count -gt 0) {
        foreach ($c in $p.Chapters) {
            $cs = 0.0
            $ce = 0.0
            try { $cs = [double]$c.start_time } catch { }
            try { $ce = [double]$c.end_time }   catch { }

            $title = "Chapter"
            if ($c.tags -and $c.tags.title) { $title = "$($c.tags.title)" }

            $metaLines.Add("[CHAPTER]")
            $metaLines.Add("TIMEBASE=1/1000")
            $metaLines.Add("START=" + [int64][math]::Round(($cs * 1000.0) + $offsetMs))
            $metaLines.Add("END="   + [int64][math]::Round(($ce * 1000.0) + $offsetMs))
            $metaLines.Add("title=" + (Escape-Meta $title))
            $chapterCount++
        }
    }
    elseif ($p.Duration -gt 0) {
        # No chapters in this one - give it a chapter named after the file, so a
        # folder of plain MP3s still comes out navigable.
        $metaLines.Add("[CHAPTER]")
        $metaLines.Add("TIMEBASE=1/1000")
        $metaLines.Add("START=" + [int64][math]::Round($offsetMs))
        $metaLines.Add("END="   + [int64][math]::Round($offsetMs + ($p.Duration * 1000.0)))
        $metaLines.Add("title=" + (Escape-Meta ([System.IO.Path]::GetFileNameWithoutExtension($p.File.Name))))
        $chapterCount++
    }

    $offsetMs += $p.Duration * 1000.0
}

$metaPath = Join-Path $env:TEMP ("kwick-merge-" + [guid]::NewGuid().ToString("N") + ".ffmeta")
try {
    [System.IO.File]::WriteAllLines($metaPath, $metaLines, (New-Object System.Text.UTF8Encoding($false)))
} catch {
    Fail ("Could not write the chapter data: " + $_.Exception.Message)
}

# Cover art: pull it out to its own little file first.
#
# Do NOT map the picture stream straight out of the book. Audiobook cover tracks
# are flagged attached_pic but carry the full runtime as their duration (57,000+
# seconds), and mapping that makes FFmpeg chew through the entire input before it
# writes a single byte - 13 minutes of 0% on a real book. Extracting the frame
# first takes 0.2s, and attaching a 40KB jpeg costs nothing.
$coverPath = $null
try {
    $v = & $ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 -- "$($files[0].FullName)" 2>$null
    if ($v) {
        $coverExt = if ("$v" -match 'png') { ".png" } else { ".jpg" }
        $candidate = Join-Path $env:TEMP ("kwick-merge-cover-" + [guid]::NewGuid().ToString("N") + $coverExt)
        & $ffmpeg -hide_banner -v error -y -i "$($files[0].FullName)" -map 0:v:0 -frames:v 1 -c:v copy $candidate 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $candidate)) { $coverPath = $candidate }
    }
} catch { }
$hasCover = [bool]$coverPath

Write-Host " - Chapters: " -NoNewline -ForegroundColor $cDim
Write-Host $chapterCount -NoNewline -ForegroundColor $cName
Write-Host " across $($files.Count) files" -ForegroundColor $cDim
Write-Host " - Cover art: " -NoNewline -ForegroundColor $cDim
if ($hasCover) { Write-Host "yes" -ForegroundColor $cVal } else { Write-Host "none found" -ForegroundColor $cTxt }
Log "Chapters written: $chapterCount"
Log "Cover art: $hasCover"

# Build FFmpeg args using direct inputs only
$ffArgs = @(
    "-hide_banner",
    "-nostdin",
    "-y",
    "-v","error"
)

foreach ($f in $files) {
    $ffArgs += @("-i", $f.FullName)
}

# The metadata file is just another input - its index follows the audio ones
$metaIdx = $files.Count
$ffArgs += @("-i", $metaPath)

# ...and the extracted cover after that
$coverIdx = -1
if ($coverPath) {
    $coverIdx = $files.Count + 1
    $ffArgs += @("-i", $coverPath)
}

$filterInputs = for ($i = 0; $i -lt $files.Count; $i++) { "[{0}:a]" -f $i }
$filterComplex = (($filterInputs -join '') + "concat=n=$($files.Count):v=0:a=1[aout]")

$ffArgs += @(
    "-filter_complex", $filterComplex,
    "-map", "[aout]"
)

if ($coverIdx -ge 0) {
    $ffArgs += @("-map", "$($coverIdx):v:0", "-c:v", "copy", "-disposition:v:0", "attached_pic")
}

$ffArgs += @(
    "-map_metadata", "$metaIdx",
    "-map_chapters", "$metaIdx"
)

if ($ext -eq ".mp3") {
    $ffArgs += @("-c:a","libmp3lame","-q:a","2")
} else {
    # .m4a and .m4b share the MP4/AAC family
    $ffArgs += @("-c:a","aac","-b:a","96k")
}

$ffArgs += @(
    "-progress", "pipe:1",
    $tempOut
)

Wait-ForStart

Write-Host ""
Write-Host "Running FFmpeg... " -NoNewline -ForegroundColor $cTxt
Write-Host "press [Q] or [Esc] to cancel" -ForegroundColor $cName
Write-Host ""

function Format-Span([double]$sec) {
    if ($sec -lt 0) { $sec = 0 }
    if ($sec -gt 359999) { $sec = 359999 }
    # Built from TotalHours, not "hh", because these books run past 24 hours
    # and "hh" would roll over and show 25:51:48 as 01:51:48.
    # Floor, not a plain [int] cast - casting rounds, so 25.86 hours became 26.
    $ts = [timespan]::FromSeconds([math]::Round($sec))
    return "{0:00}:{1:00}:{2:00}" -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds
}

# The progress block is two lines, redrawn in place. Instead of remembering an
# absolute row (which goes stale the moment the window scrolls and leaves ghost
# bars behind), we move the cursor RELATIVE to wherever it is right now - read
# fresh each time, so scrolling can't desync it.
$script:canPos        = $false
$script:progressDrawn = $false

function Init-Progress {
    try { $null = [Console]::CursorTop; $script:canPos = $true } catch { $script:canPos = $false }
    $script:progressDrawn = $false
}

function Show-Progress([double]$pct, [double]$elapsedSec, [double]$etaSec) {
    $width = 30
    $filled = [int][math]::Round(($pct / 100.0) * $width)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $width) { $filled = $width }

    # After a draw the cursor sits at the end of line 2. To redraw, step up one
    # line (to line 1) at column 0 - computed from the CURRENT cursor row.
    if ($script:canPos) {
        if ($script:progressDrawn) {
            try {
                $now = [Console]::CursorTop
                [Console]::SetCursorPosition(0, [math]::Max(0, $now - 1))
            } catch { }
        }
    } else {
        Write-Host -NoNewline "`r"
    }

    # Line 1 - ends with a newline, which puts us on line 2
    Write-Host -NoNewline "Progress: " -ForegroundColor $cDim
    Write-Host -NoNewline ("{0,6:N1}%" -f $pct) -ForegroundColor $cName
    Write-Host -NoNewline " [" -ForegroundColor $cDim
    Write-Host -NoNewline ("█" * $filled) -ForegroundColor $cVal
    Write-Host -NoNewline ("░" * ($width - $filled)) -ForegroundColor $cDim
    Write-Host -NoNewline "]   " -ForegroundColor $cDim
    Write-Host ("Elapsed " + (Format-Span $elapsedSec) + "      ") -ForegroundColor $cTxt

    # Line 2 - no trailing newline, so the cursor parks at its end for next time
    if ($etaSec -ge 0) {
        Write-Host -NoNewline ("                ETA " + (Format-Span $etaSec) + " remaining      ") -ForegroundColor $cDim
    } else {
        Write-Host -NoNewline "                ETA --:--:-- (estimating)      " -ForegroundColor $cDim
    }

    $script:progressDrawn = $true
}

function Quote-Arg([string]$a) {
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

# Tie FFmpeg's life to this script's. Closing the window kills PowerShell without
# running any cleanup, and FFmpeg - a separate process - would otherwise carry on
# encoding forever with nobody left to rename the file or stop it. A Job Object
# with KILL_ON_JOB_CLOSE makes Windows itself kill the child when we die, however
# we die: X button, Task Manager, crash.
$script:jobReady = $false
try {
    if (-not ("KwickJob" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class KwickJob
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateJobObject(IntPtr a, string lpName);

    [DllImport("kernel32.dll")]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll")]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }

    static IntPtr job = IntPtr.Zero;

    public static bool Init()
    {
        job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) { return false; }

        var ext = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        ext.BasicLimitInformation.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE

        int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr p = Marshal.AllocHGlobal(len);
        Marshal.StructureToPtr(ext, p, false);
        bool ok = SetInformationJobObject(job, 9, p, (uint)len); // ExtendedLimitInformation
        Marshal.FreeHGlobal(p);
        return ok;
    }

    public static bool Add(IntPtr processHandle)
    {
        if (job == IntPtr.Zero) { return false; }
        return AssignProcessToJobObject(job, processHandle);
    }
}
"@
    }
    $script:jobReady = [KwickJob]::Init()
} catch {
    $script:jobReady = $false
}

function Test-CancelKey {
    # Drain anything typed; Q or Esc means stop.
    #
    # IncludeKeyUp matters: ReadKey with only IncludeKeyDown will BLOCK when the
    # pending event is a key-up (e.g. releasing [Y] at the start prompt leaves one
    # behind). KeyAvailable says "yes" and then ReadKey waits forever for a keydown
    # that never comes - that is exactly what froze the merge at 0%.
    try {
        while ($Host.UI.RawUI.KeyAvailable) {
            $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown,IncludeKeyUp")
            if ($k.KeyDown -and ($k.VirtualKeyCode -eq 81 -or $k.VirtualKeyCode -eq 27)) {
                return $true
            }
        }
    } catch { }
    return $false
}

Init-Progress
Show-Progress 0.0 0.0 -1

$hadError  = $false
$cancelled = $false
$exitCode  = 1

# Run FFmpeg as a child process we hold a handle on, so a keypress can kill it.
# (A plain pipeline would block and leave no way to interrupt it.)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $ffmpeg
$psi.Arguments              = (($ffArgs | ForEach-Object { Quote-Arg $_ }) -join ' ')
$psi.UseShellExecute        = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow         = $true

$errText = ""

try {
    $proc = [System.Diagnostics.Process]::Start($psi)

    # Hand FFmpeg to the job object, so closing this window takes it down too
    if ($script:jobReady) {
        try {
            if ([KwickJob]::Add($proc.Handle)) { Log "FFmpeg attached to job object" }
            else { Log "Could not attach FFmpeg to the job object" }
        } catch { Log ("Job attach failed: " + $_.Exception.Message) }
    }

    # Drain stderr in the background. If we left it unread, a chatty FFmpeg would
    # fill the 4KB pipe, block forever, and hang the whole script.
    $errTask = $proc.StandardError.ReadToEndAsync()

    $watch    = [System.Diagnostics.Stopwatch]::StartNew()
    $lineTask = $proc.StandardOutput.ReadLineAsync()
    $lastDraw = -1.0
    $pct      = 0.0
    $audioSec = 0.0

    while ($true) {
        # Never block: if no line arrives within 200ms we still get to check for [Q]
        if ($lineTask.Wait(200)) {
            $text = $lineTask.Result
            if ($null -eq $text) { break }

            if ($text.Trim().Length -gt 0) {
                $logLines.Add("FFMPEG: " + $text) | Out-Null

                if ($text -match '^out_time_ms=(\d+)$') {
                    $audioSec = [double]$matches[1] / 1000000.0
                    $pct = [math]::Min(100.0, [math]::Max(0.0, ($audioSec / $totalSec) * 100.0))
                }
                elseif ($text -match '^progress=end$') {
                    $pct = 100.0
                }
            }

            $lineTask = $proc.StandardOutput.ReadLineAsync()
        }

        # Redraw a few times a second - drawing on every progress line is too slow
        $now = $watch.Elapsed.TotalSeconds
        if (($now - $lastDraw) -ge 0.2) {
            $lastDraw = $now
            $eta = -1.0
            if ($audioSec -gt 1.0 -and $totalSec -gt $audioSec) {
                $eta = $now * (($totalSec - $audioSec) / $audioSec)
            }
            Show-Progress $pct $now $eta
        }

        if (Test-CancelKey) {
            $cancelled = $true
            try { $proc.Kill() } catch { }
            break
        }
    }

    $proc.WaitForExit()
    $exitCode = $proc.ExitCode

    if (-not $cancelled) { Show-Progress $pct $watch.Elapsed.TotalSeconds 0 }

    try { $errText = $errTask.Result } catch { }

    if ($errText -and -not $cancelled) {
        foreach ($el in ($errText -split "`r?`n")) {
            if ($el.Trim().Length -gt 0) {
                $logLines.Add("FFMPEG-ERR: " + $el) | Out-Null
                $hadError = $true
                Write-Host ""
                Write-Host $el -ForegroundColor $cBad
            }
        }
    }
}
catch {
    $hadError = $true
    Log ("EXCEPTION: " + $_.Exception.Message)
    Log ("STACK: " + $_.ScriptStackTrace)
}

# The chapter and cover files have done their job, whatever happened next
foreach ($tmp in @($metaPath, $coverPath)) {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) {
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction Stop } catch { }
    }
}

Write-Host ""
Write-Host ""
Write-Host "-----------------------------------" -ForegroundColor $cDim

if ($cancelled) {
    Write-Host ""
    Write-Host "CANCELLED" -NoNewline -ForegroundColor $cName
    Write-Host " - nothing was changed, your files are untouched." -ForegroundColor $cTxt
    Log "CANCELLED by user during merge"

    if (Test-Path -LiteralPath $tempOut) {
        try {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction Stop
            Log "Removed the part-finished temp file"
        } catch {
            Log ("Could not remove temp file: " + $_.Exception.Message)
        }
    }

    Wait-ToClose
    exit 0
}

Write-Host "FFmpeg exit code: $exitCode" -ForegroundColor $cDim
Log "FFmpeg exit code: $exitCode"

if ($exitCode -eq 0 -and (Test-Path -LiteralPath $tempOut)) {
    # Merge worked. Now put the temp file in place of the real output name.
    try {
        if (Test-Path -LiteralPath $outFile) {
            Remove-ToRecycleBin $outFile
        }
        Rename-Item -LiteralPath $tempOut -NewName (Split-Path -Leaf $outFile) -ErrorAction Stop
        Write-Host ""
        Write-Host "SUCCESS: " -NoNewline -ForegroundColor $cVal
        Write-Host (Split-Path -Leaf $outFile) -NoNewline -ForegroundColor $cName
        Write-Host " created" -ForegroundColor $cVal
        Write-Host "Output: " -NoNewline -ForegroundColor $cDim
        Write-Host $outFile -ForegroundColor $cTxt
        Log "SUCCESS: Output created"

        if ($deleteSources) {
            Write-Host ""
            Write-Host "Removing source files..." -ForegroundColor $cDim
            foreach ($f in $files) {
                # The merged file keeps its name; never remove it
                if ($f.FullName -eq $outFile) { continue }
                if (-not (Test-Path -LiteralPath $f.FullName)) { continue }
                try {
                    Remove-ToRecycleBin $f.FullName
                } catch {
                    Write-Host "Could not remove: $($f.Name)" -ForegroundColor $cBad
                    Log ("Could not remove source: " + $f.FullName + " | " + $_.Exception.Message)
                }
            }
        }
    } catch {
        $hadError = $true
        Write-Host ""
        Write-Host "FAILURE: merge finished but the file could not be renamed." -ForegroundColor $cBad
        Write-Host $_.Exception.Message -ForegroundColor $cBad
        Write-Host "Merged audio is still here: $tempOut" -ForegroundColor $cName
        Log ("FAILURE: Rename failed: " + $_.Exception.Message)
        Log ("Merged audio left at: " + $tempOut)
    }
} else {
    $hadError = $true
    Write-Host ""
    Write-Host "FAILURE: output was NOT created" -ForegroundColor $cBad
    Log "FAILURE: Output was NOT created"

    if (Test-Path -LiteralPath $tempOut) {
        try {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction Stop
            Log "Cleaned up partial temp file: $tempOut"
        } catch {
            Log ("Could not clean up temp file: " + $_.Exception.Message)
        }
    }
}

if ($hadError -or $exitCode -ne 0) {
    Flush-Log $logPath
    Write-Host ""
    Write-Host "Log written:"
    Write-Host " - $logPath"
}

Wait-ToClose
exit