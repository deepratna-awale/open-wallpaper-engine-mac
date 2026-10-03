# Opens one project on monitor 0 (second screen) and screenshots it at the given times after the open command.
param([string]$Name, [double[]]$At)
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$out = Join-Path $PSScriptRoot 'shots'; New-Item -ItemType Directory -Force $out | Out-Null
Add-Type -Name D -Namespace W -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);'
[W.D]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
& "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 0; Start-Sleep 2
& "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\myprojects\$Name\project.json" -monitor 0
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($t in $At) {
  while ($sw.Elapsed.TotalSeconds -lt $t) { Start-Sleep -Milliseconds 10 }
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $bmp.Save((Join-Path $out ("{0}_t{1}.png" -f $Name, $t))); $g.Dispose(); $bmp.Dispose()
}
"$Name switch=$(([IO.File]::ReadAllText("$we\config.json")).Contains("myprojects/$Name/"))"
