# Clears the editor's Log window, clicks Run Preview, and polls the Log window's UIA text elements every ~150 ms,
# collecting every unique "BP ..." line (the panel keeps only the last ~77 lines). Writes them in time order.
param([string]$Out, [int]$Seconds = 12)
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
$seen = @{}; $sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
  foreach ($e in $box.FindAll('Descendants', $tc)) { $n = $e.Current.Name; if ($n -match 'BP (\S+)' -and -not $seen.ContainsKey($n)) { $seen[$n] = [double]$Matches[1] } }
  Start-Sleep -Milliseconds 100
}
$lines = $seen.GetEnumerator() | sort Value | % { $_.Key -replace '^Log:\s*', '' }
[IO.File]::WriteAllLines($Out, [string[]]$lines)
"collected $($lines.Count) BP lines -> $Out"
