# Opens owe_zoom1 / owe_zoom2 on monitor 2 and saves screenshots at fixed delays after the open command.
param([double[]]$At = @(1.5, 3.0, 6.0))
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$out = Join-Path $PSScriptRoot 'zoom'; New-Item -ItemType Directory -Force $out | Out-Null
Add-Type -Name D -Namespace W -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);'
[W.D]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
function Shot($p) { $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $bmp.Save($p); $g.Dispose(); $bmp.Dispose() }
foreach ($z in 1, 2) {
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 0; Start-Sleep 3
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\myprojects\owe_zoombox$z\project.json" -monitor 0
  $sw = [Diagnostics.Stopwatch]::StartNew()
  foreach ($t in $At) { while ($sw.Elapsed.TotalSeconds -lt $t) { Start-Sleep -Milliseconds 10 }; Shot (Join-Path $out ("zoombox{0}_t{1}.png" -f $z, $t)) }
  $ok = ([IO.File]::ReadAllText("$we\config.json")).Contains("owe_zoombox$z"); "zoom $z switch confirmed: $ok"
}

