# Drives the open Particle Editor: for every category (+ button), adds each component once and records its panel
# (labels, control types, slider min/max, values = add-defaults, dropdown options). Nothing is saved to disk.
param([int[]]$Categories = @(0, 1, 2, 3), [int]$Limit = 999, [string[]]$Only = @(), [string]$OutFile = 'panels_raw.json')
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Mouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
}
"@
$Headers = @(' Renderers', ' Emitters', ' Initializers', ' Operators', ' Children')
$CatNames = @('renderer', 'emitter', 'initializer', 'operator', 'children')
$out = Join-Path $PSScriptRoot 'editor_observed'; New-Item -ItemType Directory -Force $out | Out-Null

function Click-El($e) {
  if (Invoke-El $e) { return }
  $r = $e.Current.BoundingRectangle
  [Mouse]::Click([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
}

function Dialog-Items($doc) {
  # Texts between the dialog description and the OK button are the item tiles.
  $all = Get-All $doc; $in = $false; $items = @()
  foreach ($e in $all) {
    $n = $e.Current.Name.Trim(); $t = $e.Current.ControlType.ProgrammaticName
    if ($t -eq 'ControlType.Edit' -and $n -eq 'Search') { $in = $true; continue }
    if ($in -and $t -eq 'ControlType.Button' -and $n -eq 'OK') { break }
    if ($in -and $t -eq 'ControlType.Text' -and $n) { $items += $e }
  }
  $items
}

# Panel of the selected component: controls after its title text, up to the stats overlay.
function Read-ComponentPanel($doc, [string]$title) {
  $all = Get-All $doc; $start = $false; $label = ''; $rows = @(); $pendingOptions = $null
  $first = -1; for ($j = 0; $j -lt $all.Count; $j++) { if ($all[$j].Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and $all[$j].Current.Name.Trim() -eq $title) { $first = $j } }
  for ($i = [math]::Max(0, $first); $i -lt $all.Count; $i++) {
    $e = $all[$i]; $c = $e.Current; $t = $c.ControlType.ProgrammaticName.Replace('ControlType.', ''); $n = $c.Name.Trim()
    if (-not $start) { if ($t -eq 'Text' -and $n -eq $title) { $start = $true }; continue }
    if ($n -eq 'Particle count:') { break }
    if ($t -eq 'Text' -and $n) { if (-not $pendingOptions) { $label = $n }; continue }
    if ($t -in 'Slider', 'Spinner') {
      $rp = $null; $row = [ordered]@{ label = $label; control = $t }
      if ($e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rp)) { $row.min = $rp.Current.Minimum; $row.max = $rp.Current.Maximum; $row.value = $rp.Current.Value }
      $rows += [pscustomobject]$row
    } elseif ($t -eq 'CheckBox') {
      $tp = $null; $st = if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$tp)) { "$($tp.Current.ToggleState)" } else { '?' }
      $rows += [pscustomobject][ordered]@{ label = $label; control = 'CheckBox'; value = $st }
    } elseif ($t -eq 'Button' -and $n -and $n -notin 'Apply','Documentation','OK','Cancel') {
      $pendingOptions = [ordered]@{ label = $label; control = 'Combo'; value = $n; options = @() }
    } elseif ($t -eq 'ListItem' -and $pendingOptions) {
      if ($n) { $pendingOptions.options += $n }
    } elseif ($t -eq 'List' -and $pendingOptions -and $pendingOptions.options.Count) {
      $rows += [pscustomobject]$pendingOptions; $pendingOptions = $null
    }
    if ($pendingOptions -and $t -notin 'Button', 'ListItem', 'List', 'Hyperlink' -and $pendingOptions.options.Count) { $rows += [pscustomobject]$pendingOptions; $pendingOptions = $null }
  }
  if ($pendingOptions) { $rows += [pscustomobject]$pendingOptions }
  $rows
}

$result = @{}
foreach ($cat in $Categories) {
  $doc = Get-EditorDoc
  Click-El (Find-ByName $doc '+' 'Hyperlink' $cat); Start-Sleep 2
  $names = @(Dialog-Items (Get-EditorDoc) | % { $_.Current.Name.Trim() })
  Click-El (Find-ByName (Get-EditorDoc) 'Cancel' 'Button'); Start-Sleep 1
  "== $($CatNames[$cat]): $($names.Count) items: $($names -join ', ')"
  $k = 0
  foreach ($name in $names) {
    if ($Only -and $Only -notcontains $name) { continue }
    if ($k++ -ge $Limit) { break }
    $doc = Get-EditorDoc
    Click-El (Find-ByName $doc '+' 'Hyperlink' $cat); Start-Sleep 2
    $tile = Dialog-Items (Get-EditorDoc) | ? { $_.Current.Name.Trim() -eq $name } | Select -First 1
    if (-not $tile) { "  $name : tile not found"; Click-El (Find-ByName (Get-EditorDoc) 'Cancel' 'Button'); continue }
    Click-El $tile; Start-Sleep 1
    Click-El (Find-ByName (Get-EditorDoc) 'OK' 'Button'); Start-Sleep 2
    $doc = Get-EditorDoc
    # the new component is the last hyperlink with this name; select it so its panel shows
    $links = @(Get-All $doc | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' -and $_.Current.Name.Trim() -eq $name })
    # rely on the editor auto-selecting the newly added component
    $panel = Read-ComponentPanel (Get-EditorDoc) $name
    $result["$($CatNames[$cat]):$name"] = $panel
    "  {0,-34} {1} controls" -f $name, @($panel).Count
    $result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out $OutFile)
    # remove the component we just added: last link with this name inside this category, then the blank-named 'x' link right after it
    $links = @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' })
    $hdr = -1; for ($q = 0; $q -lt $links.Count; $q++) { if ($links[$q].Current.Name -eq $Headers[$cat]) { $hdr = $q; break } }
    $end = $links.Count; for ($q = $hdr + 2; $q -lt $links.Count; $q++) { $nn = [string]$links[$q].Current.Name; if ($nn.StartsWith(' ')) { $end = $q; break } }
    $pos = -1; for ($q = $hdr + 2; $q -lt $end; $q++) { if (([string]$links[$q].Current.Name).Trim() -eq $name) { $pos = $q } }
    if ($pos -ge 0 -and $pos + 1 -lt $end -and -not ([string]$links[$pos + 1].Current.Name).Trim()) { Click-El $links[$pos + 1]; Start-Sleep 1; "    removed" }
    else { "    WARNING: could not find remove button for $name - stopping"; break }
  }
}
"done"



