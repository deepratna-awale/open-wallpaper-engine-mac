# Applies each fxgal_* project on the second monitor, captures a still at ~5 s and a 3 s clip, and logs WE errors.
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$out = Join-Path $PSScriptRoot "captures"; New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $PSScriptRoot "capture.log"; Set-Content $log ""
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
function LogTail($from) { $fs = [IO.File]::Open("$we\log.txt", 'Open', 'Read', 'ReadWrite'); $fs.Seek($from, 'Begin') | Out-Null; $t = (New-Object IO.StreamReader $fs).ReadToEnd(); $fs.Close(); $t }

foreach ($p in Get-ChildItem "$we\projects\myprojects" -Directory | ? { $_.Name -like 'fxgal_*' -or ($_.Name -like 'effecttest-*' -and $_.Name -ne 'effecttest-blank') } | Sort-Object Name) {
  $name = $p.Name -replace '^fxgal_', '' -replace '^effecttest-', 'user_'
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 1; Start-Sleep 2
  $mark = (Get-Item "$we\log.txt").Length
  & "$we\wallpaper64.exe" -control openWallpaper -file "$($p.FullName)\project.json" -monitor 1
  Start-Sleep 5
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $out "$name.png")); $g.Dispose(); $bmp.Dispose()
  & ffmpeg -loglevel error -y -f gdigrab -framerate 30 -offset_x $b.X -offset_y $b.Y -video_size "$($b.Width)x$($b.Height)" -t 3 -i desktop -c:v libx264 -crf 28 -pix_fmt yuv420p (Join-Path $out "$name.mp4")
  $errs = (LogTail $mark).Trim()
  Add-Content $log ("== $name " + $(if ($errs) { "ERRORS:`n$errs" } else { "ok" }))
}
Add-Content $log "done"

