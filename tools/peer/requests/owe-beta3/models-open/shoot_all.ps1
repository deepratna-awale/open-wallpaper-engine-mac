# Opens each mo_* project (or -Names) on monitor 0 (the second screen in the current layout), waits, screenshots it,
# and records whether the switch landed plus any new WE log.txt lines. Output: shots\<name>.png and shots\shots.log.
param([string[]]$Names, [int]$Settle = 5)
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$out = Join-Path $PSScriptRoot 'shots'; New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out 'shots.log'
Add-Type -Name D -Namespace W -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);'
[W.D]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary })[0].Bounds
if (-not $Names) { $Names = Get-ChildItem "$we\projects\myprojects" -Directory -Filter 'mo_*' | Sort-Object Name | % Name }
foreach ($n in $Names) {
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\defaultprojects\retro\project.json" -monitor 0; Start-Sleep 2
  $mark = (Get-Item "$we\log.txt").Length
  & "$we\wallpaper64.exe" -control openWallpaper -file "$we\projects\myprojects\$n\project.json" -monitor 0
  Start-Sleep $Settle
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $bmp.Save((Join-Path $out "$n.png")); $g.Dispose(); $bmp.Dispose()
  $ok = ([IO.File]::ReadAllText("$we\config.json")).Contains("myprojects/$n/")
  $fs = [IO.File]::Open("$we\log.txt", 'Open', 'Read', 'ReadWrite'); $fs.Seek($mark, 'Begin') | Out-Null; $t = (New-Object IO.StreamReader $fs).ReadToEnd().Trim(); $fs.Close()
  $t = ($t -split "`r?`n" | ? { $_ -notmatch 'pf_remapclamp|Failed opening: scene.json' }) -join ' | '
  "$n switch=$ok log=[$t]" | Tee-Object -FilePath $log -Append
}
