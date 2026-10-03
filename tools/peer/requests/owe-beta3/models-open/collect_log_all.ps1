# Like ../../bone-physics/response/collect_editor_log.ps1, but keeps every Log-window line (script output and errors),
# in first-seen order. Clears the log, clicks Run Preview, polls for -Seconds, then clicks Stop Preview.
param([string]$Out, [int]$Seconds = 8)
. (Join-Path $PSScriptRoot '..\..\..\models_gt\ed.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Threading;
public static class Mc { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,IntPtr e);
 public static void Click(int x,int y){ SetCursorPos(x,y); Thread.Sleep(150); mouse_event(2,0,0,0,IntPtr.Zero); Thread.Sleep(80); mouse_event(4,0,0,0,IntPtr.Zero); Thread.Sleep(300);} }
"@
[Mc]::SetProcessDPIAware() | Out-Null
$box = EdDoc; $tc = New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
[Mc]::Click(1608, 267)   # clear log
[Mc]::Click(998, 91)     # Run Preview
$seen = [ordered]@{}; $sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
  foreach ($e in $box.FindAll('Descendants', $tc)) { $n = $e.Current.Name; if ($n -match '^(Log|Error|Warning|Exception)|MO |rror' -and -not $seen.Contains($n)) { $seen[$n] = 1 } }
  Start-Sleep -Milliseconds 100
}
[Mc]::Click(998, 91)     # Stop Preview
[IO.File]::WriteAllLines($Out, [string[]]@($seen.Keys))
"collected $($seen.Count) lines -> $Out"
