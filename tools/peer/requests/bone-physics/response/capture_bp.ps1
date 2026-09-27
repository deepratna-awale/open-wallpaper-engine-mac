# Records one bone-physics variant: 11 s 60 fps ddagrab (Desktop Duplication; gdigrab only reached ~15-25 fps) of an 800x800 region around the bar on monitor 1 (secondary
# screen), starting ~0.7 s before openWallpaper, then keeps WE's log.txt output from the run (console.log does not reach log.txt; the BP lines come from collect_editor_log.ps1).
param([string]$Project, [string]$Out)
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Add-Type -AssemblyName System.Windows.Forms
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
New-Item -ItemType Directory -Force $Out | Out-Null
# scene 1920x1080 fills the screen; the bar sits at x 960 (1160 while moved), y 540 -> crop centred on (1060, 540)
$sx = $b.Width / 1920; $cx = $b.X + [int](660 * $sx); $cy = $b.Y + [int](140 * $sx)
& "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 1; Start-Sleep 5
$mark = (Get-Item "$we\log.txt").Length
$dd = "ddagrab=output_idx=1:framerate=60:offset_x=$($cx - $b.X):offset_y=$($cy - $b.Y):video_size=800x800"   # DXGI output 1 = the wallpaper screen
$ff = Start-Process ffmpeg -ArgumentList @('-loglevel', 'error', '-y', '-f', 'lavfi', '-i', $dd,
  '-t', '11', '-vf', 'hwdownload,format=bgra', '-c:v', 'libx264', '-crf', '16', '-pix_fmt', 'yuv420p', (Join-Path $Out 'clip_60fps_800x800.mp4')) -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 700
$t0 = Get-Date
& "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\myprojects\$Project\project.json" -monitor 1
$want = "myprojects/$Project/project.json"; $ok = $false
for ($i = 0; $i -lt 6 -and -not $ok; $i++) { Start-Sleep -Milliseconds 500; $ok = ([IO.File]::ReadAllText("$we\config.json")).Contains($want) }
$ff.WaitForExit()
if (-not $ok) { "SWITCH NOT CONFIRMED"; exit 1 }
Start-Sleep 1
$fs = [IO.File]::Open("$we\log.txt", 'Open', 'Read', 'ReadWrite'); $fs.Seek($mark, 'Begin') | Out-Null; $txt = (New-Object IO.StreamReader $fs).ReadToEnd(); $fs.Close()
[IO.File]::WriteAllText((Join-Path $Out 'we_log_during_run.txt'), $txt)
$bp = @($txt -split "`r?`n" | ? { $_ -match 'BP ' })
"screen $($b.Width)x$($b.Height) at $($b.X),$($b.Y); crop at $cx,$cy; open command at $($t0.ToString('HH:mm:ss.fff')) (~0.7 s into the clip)" | Set-Content (Join-Path $Out 'capture_notes.txt')
"BP lines: $($bp.Count)"
