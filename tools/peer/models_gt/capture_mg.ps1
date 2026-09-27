# Captures for the audit session's models ground-truth request (MG1-4, MG6-8 stills). Recording starts at load;
# stills are extracted from the recordings afterwards. Each switch is verified in config.json.
param([string[]]$Steps = @('MG1', 'MG3', 'MG4', 'MG6', 'MG8', 'MG2', 'MG7'))
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$my = "$we\projects\myprojects"; $ws = "C:\Program Files (x86)\Steam\steamapps\workshop\content\431960"
$out = Join-Path $PSScriptRoot 'captures'; New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $PSScriptRoot 'capture.log'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Add-Type -AssemblyName System.Windows.Forms
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
function Log($m) { "$(Get-Date -Format HH:mm:ss) $m" | Tee-Object -FilePath $log -Append }

Add-Type -AssemblyName System.Drawing
function Grab { $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $g.Dispose(); $v = @(); for ($y = 40; $y -lt 1000; $y += 60) { for ($x = 40; $x -lt 1900; $x += 60) { $c = $bmp.GetPixel($x, $y); $v += ($c.R + $c.G + $c.B) } }; $bmp.Dispose(); , $v }
function Diff($p, $q) { $d = 0; for ($i = 0; $i -lt $p.Count; $i++) { $d += [math]::Abs($p[$i] - $q[$i]) }; $d / $p.Count / 3 }
function Record([string]$projectJson, [string]$name, [int]$seconds) { for ($attempt = 1; $attempt -le 3; $attempt++) { $before = Grab; if (RecordOnce $projectJson $name $seconds) { $after = Grab; $d = Diff $before $after; if ($d -gt 2) { Log "$name : visual change $([math]::Round($d,1)) (attempt $attempt) OK"; return } ; Log "$name : NO visual change ($([math]::Round($d,2))) on attempt $attempt - retrying"; & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 1; Start-Sleep 6 } } }
function RecordOnce([string]$projectJson, [string]$name, [int]$seconds) {
  $want = (Split-Path $projectJson -Parent) -replace '\\', '/'
  $mark = (Get-Item "$we\log.txt").Length
  $ff = Start-Process ffmpeg -ArgumentList @('-loglevel', 'error', '-y', '-f', 'gdigrab', '-framerate', '30', '-offset_x', $b.X, '-offset_y', $b.Y,
      '-video_size', "$($b.Width)x$($b.Height)", '-t', ($seconds + 1), '-i', 'desktop', '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p', (Join-Path $out "$name.mp4")) -PassThru -WindowStyle Hidden
  Start-Sleep -Milliseconds 700   # recorder warm-up; t=0 of the video is ~0.7 s before the open command
  & "$we\wallpaper64.exe" -control openWallpaper -file $projectJson -monitor 1
  $ok = $false; for ($i = 0; $i -lt 10 -and -not $ok; $i++) { Start-Sleep 1; $ok = ([IO.File]::ReadAllText("$we\config.json")).Contains($want) }
  if (-not $ok) { & "$we\wallpaper64.exe" -control openWallpaper -file $projectJson -monitor 1; Start-Sleep 2; $ok = ([IO.File]::ReadAllText("$we\config.json")).Contains($want) }
  $ff.WaitForExit()
  $fs = [IO.File]::Open("$we\log.txt", 'Open', 'Read', 'ReadWrite'); $fs.Seek($mark, 'Begin') | Out-Null; $errs = (New-Object IO.StreamReader $fs).ReadToEnd().Trim(); $fs.Close()
  Log ("$name : switch " + $(if ($ok) { 'confirmed' } else { 'NOT CONFIRMED' }) + $(if ($errs) { " | WE log: $($errs -replace '\s+', ' ')" } else { '' }))
  return $true
}

function Set-Config([hashtable]$kv) {
  Get-Process wallpaperui, wallpaper64 -EA SilentlyContinue | Stop-Process -Force; Start-Sleep 3
  $t = [IO.File]::ReadAllText("$we\config.json")
  if ($t.Length -lt 5000) { throw "config.json unexpectedly small ($($t.Length) bytes) - aborting without writing" }
  foreach ($k in $kv.Keys) { $t = [regex]::Replace($t, "(`"$k`"\s*:\s*)(`"[^`"]*`"|\d+)", "`${1}`"$($kv[$k])`"") }
  $null = $t | ConvertFrom-Json
  [IO.File]::WriteAllText("$we\config.json", $t)
  Start-Process "$we\wallpaper64.exe"; Start-Sleep 15
  Log "config set: $(($kv.GetEnumerator() | % { "$($_.Key)=$($_.Value)" }) -join ', ')"
}
function Restart-WE { Get-Process wallpaperui, wallpaper64 -EA SilentlyContinue | Stop-Process -Force; Start-Sleep 3; Start-Process "$we\wallpaper64.exe"; Start-Sleep 15; Log 'WE restarted' }

if ($Steps -contains 'MG1') {
  Record "$ws\3159348391\project.json" 'MG1_parappa_run1' 70
  Record "$ws\3159348391\project.json" 'MG1_parappa_run2' 70
  Restart-WE
  Record "$ws\3159348391\project.json" 'MG1_parappa_run3_after_restart' 70
}
if ($Steps -contains 'MG3') { foreach ($p in 'gt-additive-full', 'gt-additive-half') { Record "$my\mg_$p\project.json" "MG3_$p" 4 } }
if ($Steps -contains 'MG4') { Get-ChildItem $my -Directory -Filter 'mg_gt-rootmotion-0x*' | ? { $_.Name -ne 'mg_gt-rootmotion-0x00000' } | Sort Name | % { Record "$($_.FullName)\project.json" ("MG4_" + ($_.Name -replace '^mg_', '')) 5 } }
if ($Steps -contains 'MG6') {
  foreach ($p in 'gt-ortho-depth-near-first', 'gt-ortho-depth-far-first') { Record "$my\mg_$p\project.json" "MG6_$p" 3 }
  foreach ($v in 'shipped', 'depthon', 'depthoff') { Record "$my\mg_colmodel_$v\project.json" "MG6_colmodel_$v" 5 }
}
if ($Steps -contains 'MG8') { Record "$my\mg_colmodel_spherehidden\project.json" 'MG8_colmodel_spherehidden' 5 }
if ($Steps -contains 'MG2') {
  Set-Config @{ shadows = 'disabled' }
  Record "$ws\3455121165\project.json" 'MG2_solar_workshop' 21
  Record "$my\mg_solar_shipped\project.json" 'MG2_solar_localcopy_shipped' 21
  Record "$my\mg_solar_nosort\project.json" 'MG2_solar_localcopy_nosort' 21
}
if ($Steps -contains 'MG7') {
  foreach ($q in 'disabled', 'low', 'medium', 'high') { Set-Config @{ shadows = $q }; Record "$ws\3734636606\project.json" "MG7_cloth_shadows_$q" 11 }
}
Log 'capture done'

