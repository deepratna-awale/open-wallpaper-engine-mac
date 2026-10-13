# Restarts WE under RenderDoc, runs a qrenderdoc script (rd_timed.py with job_timed.json by default, or rd_draws.py
# with job_draws.json), then restarts WE normally on the user's wallpaper and prints the script's report.
param([string]$Script = 'rd_timed.py')
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"; $rd = "K:\DeepWorkspace\tools\renderdoc\RenderDoc_1.46_64"; $g = $PSScriptRoot
$job = if ($Script -eq 'rd_draws.py') { 'job_draws.json' } else { 'job_timed.json' }
$rep = if ($Script -eq 'rd_draws.py') { 'rd_draws_report.txt' } else { 'rd_timed_report.txt' }
Get-Process wallpaper64, wallpaperui, webwallpaper32 -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3
Start-Process "$rd\renderdoccmd.exe" -WindowStyle Hidden -ArgumentList @('capture', '-d', "`"$we`"", '-c', "$g\cap\we", "`"$we\wallpaper64.exe`"")
Start-Sleep 20
$p = Start-Process "$rd\qrenderdoc.exe" -ArgumentList @('--python', "$g\$Script") -PassThru -WindowStyle Minimized
$p.WaitForExit(300000) | Out-Null
Get-Process wallpaper64, wallpaperui, webwallpaper32, renderdoccmd, qrenderdoc -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3
Start-Process "$we\wallpaper64.exe"; Start-Sleep 15
& "$we\wallpaper64.exe" -control openWallpaper -file "C:\Program Files (x86)\Steam\steamapps\workshop\content\431960\3606529469\project.json" -monitor 0; Start-Sleep 3
Remove-Item "$g\cap\we*" -ErrorAction SilentlyContinue
Get-Content (Join-Path (Get-Content "$g\$job" -Raw | ConvertFrom-Json).out $rep)
