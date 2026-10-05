# Opens a project in WE's editor, selects its camera layer ("Probe Cam"), adds a camera path with the editor's
# own UI and keys Eye x / Center x at the given frames (timeline: frame 0 at x=809, 10 px per frame), then saves.
param([string]$Project, [string]$Keys = "0:0,30:400,60:0", [switch]$Ortho)
& (Join-Path $PSScriptRoot '..\..\..\models_gt\open_editor.ps1') -Title $Project | Out-Null; Start-Sleep 3
. (Join-Path $PSScriptRoot '..\..\..\models_gt\ed.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Threading;
public static class Mp { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,IntPtr e);
 public static void Click(int x,int y){ SetCursorPos(x,y); Thread.Sleep(300); mouse_event(2,0,0,0,IntPtr.Zero); Thread.Sleep(80); mouse_event(4,0,0,0,IntPtr.Zero); Thread.Sleep(400);}
 public static void Triple(int x,int y){ SetCursorPos(x,y); Thread.Sleep(200); for(int i=0;i<3;i++){ mouse_event(2,0,0,0,IntPtr.Zero); Thread.Sleep(30); mouse_event(4,0,0,0,IntPtr.Zero); Thread.Sleep(40);} Thread.Sleep(300);} }
"@
[Mp]::SetProcessDPIAware() | Out-Null
function SetF($x, $y, $v) { [Mp]::Triple($x, $y); [Windows.Forms.SendKeys]::SendWait("^a$v{TAB}"); Start-Sleep -m 700 }
$c = All | ? { (Clean $_.Current.Name) -eq 'Probe Cam' } | select -First 1; $r = $c.Current.BoundingRectangle
[Mp]::Click([int]($r.X + 60), [int]($r.Y + $r.Height / 2)); Start-Sleep 2
[Mp]::Click(1637, 778); Start-Sleep 3
foreach ($kv in $Keys.Split(',')) {
  $f, $v = $kv.Split(':'); [Mp]::Click(809 + 10 * [int]$f, 987); Start-Sleep 1
  SetF 1620 410 $v; SetF 1620 475 $v
}
[Windows.Forms.SendKeys]::SendWait('^s'); Start-Sleep 5
"done $Project"
