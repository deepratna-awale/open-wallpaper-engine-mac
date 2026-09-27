param([string]$Prefix = "ptcl_", [string]$OutName = "captures", [int]$ClipSec = 5, [string[]]$Names = @())
# Applies each <Prefix>* project on the second monitor, captures a still at ~6 s and a clip, and logs WE errors.
# WE sometimes drops an openWallpaper command, so each switch is verified against config.json and re-issued.
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$out = Join-Path $PSScriptRoot $OutName; New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $PSScriptRoot "$OutName.log"; if (-not $Names) { Set-Content $log "" }
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
function LogTail($from) { $fs = [IO.File]::Open("$we\log.txt", 'Open', 'Read', 'ReadWrite'); $fs.Seek($from, 'Begin') | Out-Null; $t = (New-Object IO.StreamReader $fs).ReadToEnd(); $fs.Close(); $t }

foreach ($p in Get-ChildItem "$we\projects\myprojects" -Directory -Filter "$Prefix*" | Sort-Object Name) {
  $name = $p.Name -replace '^(ptcl|ptce)_', ''
  if ($p.Name -like 'ptce_*') { $name = $p.Name }
  if ($Names -and $Names -notcontains $name) { continue }
  $mark = (Get-Item "$we\log.txt").Length
  $want = ($p.FullName -replace '\\', '/')
  $switched = $false
  for ($try = 0; $try -lt 4 -and -not $switched; $try++) {
    & "$we\wallpaper64.exe" -control openWallpaper -file "$($p.FullName)\project.json" -monitor 1
    Start-Sleep 6
    $switched = ([IO.File]::ReadAllText("$we\config.json")).Contains($want)
  }
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $out "$name.png")); $g.Dispose(); $bmp.Dispose()
  & ffmpeg -loglevel error -y -f gdigrab -framerate 30 -offset_x $b.X -offset_y $b.Y -video_size "$($b.Width)x$($b.Height)" -t $ClipSec -i desktop -c:v libx264 -crf 28 -pix_fmt yuv420p (Join-Path $out "$name.mp4")
  $errs = (LogTail $mark).Trim()
  Add-Content $log ("== $name " + $(if (-not $switched) { "SWITCH NOT CONFIRMED " } else { "" }) + $(if ($errs) { "ERRORS:`n$errs" } else { "ok" }))
}
Add-Content $log "done"
