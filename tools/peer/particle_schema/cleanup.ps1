# Removes components added by harvest.ps1: in each category keeps the first $Keep entries, deletes the rest from the end.
param([hashtable]$Keep = @{ ' Renderers' = 3; ' Emitters' = 1; ' Initializers' = 4; ' Operators' = 2 })
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Mouse2 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
}
"@
function Click-El($e) { try { if (Invoke-El $e) { return } } catch {}; $r = $e.Current.BoundingRectangle; [Mouse2]::Click([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) }

function Category-Items($doc, $header) {
  $links = @(Get-All $doc | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' })
  $i = [array]::FindIndex($links, [Predicate[object]]{ param($l) $l.Current.Name -eq $header })
  $items = @()
  for ($j = $i + 2; $j -lt $links.Count; $j++) {   # skip header and its '+'
    $n = $links[$j].Current.Name
    if ($n.StartsWith(' ')) { break }              # next category header
    if ($n.Trim()) { $items += $links[$j] }
  }
  $items
}

foreach ($h in ' Renderers', ' Emitters', ' Initializers', ' Operators') {
  $guard = 0
  while ($guard++ -lt 40) {
    $doc = Get-EditorDoc
    $items = Category-Items $doc $h
    if ($items.Count -le $Keep[$h]) { break }
    $last = $items[-1]; $name = $last.Current.Name.Trim()
    Click-El $last; Start-Sleep 1
    $links = @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' })
    $idx = [array]::FindLastIndex($links, [Predicate[object]]{ param($l) $l.Current.Name.Trim() -eq $name })
    $x = if ($idx -ge 0 -and $idx + 1 -lt $links.Count -and -not $links[$idx + 1].Current.Name.Trim()) { $links[$idx + 1] }
    if (-not $x) { "  $h : no remove button next to '$name'"; break }
    Click-El $x; Start-Sleep 1
    "  removed $($h.Trim()): $name"
  }
  "$($h.Trim()): $((Category-Items (Get-EditorDoc) $h).Count) left"
}
