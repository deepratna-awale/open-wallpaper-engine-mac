# 501 captures: copies the p501_* projects into myprojects, then per project opens it on the second screen
# (WE -monitor 0 in the current layout), records a 4 s 60->30 fps ddagrab clip of DXGI output 1 for path projects,
# and saves stills at the shots.json times. Output: captures\mo2_501_*.png / .mp4
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$here = $PSScriptRoot; $out = Join-Path $here 'captures'; New-Item -ItemType Directory -Force $out | Out-Null
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Add-Type -Name D -Namespace W -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);'
[W.D]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
function Shot($p) { $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $bmp.Save($p); $g.Dispose(); $bmp.Dispose() }
foreach ($d in Get-ChildItem (Join-Path $here 'projects') -Directory) { Copy-Item -Recurse -Force $d.FullName "$we\projects\myprojects\" }
$shots = (Get-Content (Join-Path $here 'shots.json') -Raw | ConvertFrom-Json).shots
foreach ($s in $shots) {
  $tag = $s.project -replace '^p501_', ''
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 0; Start-Sleep 3
  $ff = $null
  if ($s.clip) {
    $ff = Start-Process ffmpeg -PassThru -WindowStyle Hidden -ArgumentList @('-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'ddagrab=output_idx=1:framerate=30', '-t', [string]$s.clip.seconds, '-vf', 'hwdownload,format=bgra', '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p', (Join-Path $out "mo2_501_$tag.mp4"))
    Start-Sleep -Milliseconds 400
  }
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\myprojects\$($s.project)\project.json" -monitor 0
  $sw = [Diagnostics.Stopwatch]::StartNew()
  foreach ($t in $s.stills) { while ($sw.Elapsed.TotalSeconds -lt $t) { Start-Sleep -Milliseconds 5 }; Shot (Join-Path $out ("mo2_501_{0}_t{1}.png" -f $tag, $t)) }
  if ($ff) { $ff.WaitForExit() } else { Start-Sleep 1 }
  "$($s.project) switch=$(([IO.File]::ReadAllText("$we\config.json")).Contains("myprojects/$($s.project)/"))"
}
