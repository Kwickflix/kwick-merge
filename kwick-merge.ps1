param(
    [string]$Folder
)

<#
Kwick_Merge
WORKING + QUIET + CLEAN ONE-LINE PROGRESS (PowerShell 5.1 safe)

• Drag-drop folder support via -Folder
• Natural sort
• No concat list
• Minimal output
• Shows % + ASCII bar
• Output name = folder name, or type your own at the prompt
• Auto output type = MP3, M4A, or M4B (based on inputs)
• Optionally deletes the source files (Recycle Bin) after a successful merge
• Merges to a temp file, renamed at the end, so nothing is lost on failure
• On ANY error: writes a log next to where the output would be
• Always pauses at end (ENTER or SPACE)
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

# Estimate total duration (seconds) using ffprobe
$totalSec = 0.0
foreach ($f in $files) {
    $dur = & $ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 -- "$($f.FullName)" 2>$null
    if ($dur) {
        try { $totalSec += [double]$dur } catch {}
    }
}
if ($totalSec -le 0) { $totalSec = 1.0 }

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

$filterInputs = for ($i = 0; $i -lt $files.Count; $i++) { "[{0}:a]" -f $i }
$filterComplex = (($filterInputs -join '') + "concat=n=$($files.Count):v=0:a=1[aout]")

$ffArgs += @(
    "-filter_complex", $filterComplex,
    "-map", "[aout]"
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

# Row the progress block starts on, so it can be overwritten instead of repeated
$script:barTop = -1
$script:canPos = $false

function Init-Progress {
    try {
        $script:barTop = [Console]::CursorTop
        $script:canPos = $true
    } catch {
        $script:canPos = $false
    }
}

function Show-Progress([double]$pct, [double]$elapsedSec, [double]$etaSec) {
    $width = 30
    $filled = [int][math]::Round(($pct / 100.0) * $width)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $width) { $filled = $width }

    if ($script:canPos) {
        try { [Console]::SetCursorPosition(0, $script:barTop) } catch { }
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

    # Line 2 - deliberately NO trailing newline, or the window would scroll
    # every redraw and the saved row would drift.
    if ($etaSec -ge 0) {
        Write-Host -NoNewline ("                ETA " + (Format-Span $etaSec) + " remaining      ") -ForegroundColor $cDim
    } else {
        Write-Host -NoNewline "                ETA --:--:-- (estimating)      " -ForegroundColor $cDim
    }

    # Re-anchor from where we actually ended up, so a scroll can't desync us
    if ($script:canPos) {
        try { $script:barTop = [Console]::CursorTop - 1 } catch { }
    }
}

function Quote-Arg([string]$a) {
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
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