param([string]$OutName = "cursor_captures", [int]$SettleSec = 4, [int]$ClipSec = 4)
# Cursor capture request (OpenWallpaperEngine docs/test-risks.md FX1). Run after build_cursor_request.py.
# For each curs_* project in myprojects: opens it on the second monitor (as capture_gallery.ps1 does),
# puts the cursor at each still's point on that monitor, waits 1 s, and saves the screen;
# for a sweep, records a clip while the cursor crosses the layer and logs every cursor position.
# The cursor must be free to move onto monitor 2: keep this window on the primary monitor, don't touch
# the mouse while it runs, and leave WE's mouse interaction on (Settings > General).
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$out = Join-Path $PSScriptRoot $OutName; New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out "capture.log"; Set-Content $log ""
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class OweCursor {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
}
"@
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
Add-Content $log ("monitor 2 bounds: " + $b.X + "," + $b.Y + " " + $b.Width + "x" + $b.Height)
function Shot($path) {
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
  $bmp.Save($path); $g.Dispose(); $bmp.Dispose()
}
function Where() { $p = New-Object OweCursor+POINT; [OweCursor]::GetCursorPos([ref]$p) | Out-Null; "$($p.X - $b.X),$($p.Y - $b.Y)" }
function LogTail($from) { $fs = [IO.File]::Open("$we\log.txt", 'Open', 'Read', 'ReadWrite'); $fs.Seek($from, 'Begin') | Out-Null; $t = (New-Object IO.StreamReader $fs).ReadToEnd(); $fs.Close(); $t }

$shots = Get-Content (Join-Path $PSScriptRoot "shots.json") -Raw | ConvertFrom-Json
foreach ($s in $shots) {
  $proj = "$we\projects\myprojects\$($s.project)\project.json"
  # Park the cursor at monitor 2's top-left corner, off every layer, before the wallpaper opens.
  [OweCursor]::SetCursorPos($b.X + 40, $b.Y + 40) | Out-Null
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 1; Start-Sleep 2
  $mark = (Get-Item "$we\log.txt").Length
  & "$we\wallpaper64.exe" -control openWallpaper -file $proj -monitor 1
  Start-Sleep $SettleSec
  Shot (Join-Path $out "$($s.project)_park.png")
  foreach ($p in $s.stills) {
    [OweCursor]::SetCursorPos($b.X + [int]$p[0], $b.Y + [int]$p[1]) | Out-Null
    Start-Sleep -Milliseconds 1000
    $at = Where
    Shot (Join-Path $out "$($s.project)_$($p[0])_$($p[1]).png")
    Add-Content $log "$($s.project) still $($p[0]),$($p[1]) cursor $at"
  }
  if ($s.sweep) {
    $clip = Join-Path $out "$($s.project).mp4"
    $csv = Join-Path $out "$($s.project)_path.csv"
    Set-Content $csv "ms,x,y"
    [OweCursor]::SetCursorPos($b.X + [int]$s.sweep.start[0], $b.Y + [int]$s.sweep.start[1]) | Out-Null
    Start-Sleep -Milliseconds 1500
    $ff = Start-Process ffmpeg -PassThru -NoNewWindow -ArgumentList @("-loglevel", "error", "-y", "-f", "gdigrab", "-draw_mouse", "0",
      "-framerate", "30", "-offset_x", $b.X, "-offset_y", $b.Y, "-video_size", "$($b.Width)x$($b.Height)", "-t", $ClipSec,
      "-i", "desktop", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", $clip)
    $ffStart = [DateTime]::Now
    Start-Sleep -Milliseconds 800   # ffmpeg starts; the cursor waits at the start
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Add-Content $log ("$($s.project) ffmpeg launched " + $ffStart.ToString("HH:mm:ss.fff") + ", sweep starts " + [DateTime]::Now.ToString("HH:mm:ss.fff"))
    $x0 = [double]$s.sweep.start[0]; $y0 = [double]$s.sweep.start[1]
    $x1 = [double]$s.sweep.end[0]; $y1 = [double]$s.sweep.end[1]; $T = [double]$s.sweep.seconds * 1000
    while ($sw.ElapsedMilliseconds -le $T) {
      $f = [Math]::Min(1.0, $sw.ElapsedMilliseconds / $T)
      $x = [int][Math]::Round($x0 + ($x1 - $x0) * $f); $y = [int][Math]::Round($y0 + ($y1 - $y0) * $f)
      [OweCursor]::SetCursorPos($b.X + $x, $b.Y + $y) | Out-Null
      Add-Content $csv "$($sw.ElapsedMilliseconds),$x,$y"
      Start-Sleep -Milliseconds 8
    }
    [OweCursor]::SetCursorPos($b.X + [int]$x1, $b.Y + [int]$y1) | Out-Null
    Start-Sleep -Milliseconds 300
    Shot (Join-Path $out "$($s.project)_after.png")
    $ff.WaitForExit()
    Add-Content $log "$($s.project) sweep logged, cursor now $(Where)"
  }
  $errs = (LogTail $mark).Trim()
  Add-Content $log ("== $($s.project) " + $(if ($errs) { "ERRORS:`n$errs" } else { "ok" }))
}
Add-Content $log "done"
