# Restarts WE under RenderDoc, runs rd_timed.py with job_timed.json, then restarts WE normally on the user's wallpaper.
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"; $rd = "K:\DeepWorkspace\tools\renderdoc\RenderDoc_1.46_64"; $g = $PSScriptRoot
Get-Process wallpaper64, wallpaperui, webwallpaper32 -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3
Start-Process "$rd\renderdoccmd.exe" -WindowStyle Hidden -ArgumentList @('capture', '-d', "`"$we`"", '-c', "$g\cap\we", "`"$we\wallpaper64.exe`"")
Start-Sleep 20
$p = Start-Process "$rd\qrenderdoc.exe" -ArgumentList @('--python', "$g\rd_timed.py") -PassThru -WindowStyle Minimized
$p.WaitForExit(300000) | Out-Null
Get-Process wallpaper64, wallpaperui, webwallpaper32, renderdoccmd, qrenderdoc -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3
Start-Process "$we\wallpaper64.exe"; Start-Sleep 15
& "$we\wallpaper64.exe" -control openWallpaper -file "C:\Program Files (x86)\Steam\steamapps\workshop\content\431960\3606529469\project.json" -monitor 0; Start-Sleep 3
Remove-Item "$g\cap\we*" -ErrorAction SilentlyContinue
Get-Content (Join-Path (Get-Content "$g\job_timed.json" -Raw | ConvertFrom-Json).out 'rd_timed_report.txt')
