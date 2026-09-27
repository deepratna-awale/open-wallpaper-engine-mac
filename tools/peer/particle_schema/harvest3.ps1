# Particle editor harvest v2: for each item in a category's add dialog -> add it, select it, read its panel, remove it.
# Assumes the category starts EMPTY (so the new component is the only item there). Nothing is saved to disk.
param([string]$Category = 'Operators', [string]$OutFile = 'operators.json', [string[]]$Only = @(), [int]$Limit = 999)
. (Join-Path $PSScriptRoot 'uia.ps1')
. (Join-Path $PSScriptRoot 'panel_reader.ps1')
$out = Join-Path $PSScriptRoot 'editor_observed'; $out = Join-Path $PSScriptRoot 'editor_observed_v3'; New-Item -ItemType Directory -Force $out | Out-Null
$ascii = { param($s) (([string]$s) -replace '[^\x20-\x7e]', '').Trim() }

function Links { @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' }) }
function Cat-Range {  # returns @(headerIndex, endIndex) in Links
  $L = Links; $h = -1
  for ($i = 0; $i -lt $L.Count; $i++) { if ((& $ascii $L[$i].Current.Name) -eq $Category) { $h = $i; break } }
  $e = $L.Count
  for ($i = $h + 2; $i -lt $L.Count; $i++) { $n = [string]$L[$i].Current.Name; if ($n -match '^[^\x20-\x7e]\s*\w' -and $n -notmatch '[\x20-\x7e]\s*[^\x20-\x7e]$') { $e = $i; break } }
  , @($L, $h, $e)
}
function Plus { $r = Cat-Range; $r[0][$r[1] + 1] }
function Dialog-Tiles {
  $all = Get-All (Get-EditorDoc); $in = $false; $t = @()
  foreach ($x in $all) {
    $n = ([string]$x.Current.Name).Trim(); $ty = $x.Current.ControlType.ProgrammaticName
    if ($ty -eq 'ControlType.Edit' -and $n -eq 'Search') { $in = $true; continue }
    if ($in -and $ty -eq 'ControlType.Button' -and $n -eq 'OK') { break }
    if ($in -and $ty -eq 'ControlType.Text' -and $n) { $t += $x }
  }
  $t
}
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker

function Read-Panel([string]$title) {
  $all = Get-All (Get-EditorDoc); $first = -1
  for ($j = 0; $j -lt $all.Count; $j++) { if ($all[$j].Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and ([string]$all[$j].Current.Name).Trim() -eq $title) { $first = $j } }
  $label = ''; $rows = @(); $combo = $null
  for ($i = $first + 1; $i -lt $all.Count; $i++) {
    $e = $all[$i]; $c = $e.Current; $t = $c.ControlType.ProgrammaticName.Replace('ControlType.', ''); $n = ([string]$c.Name).Trim()
    if ($n -eq 'Particle count:') { break }
    if ($combo -and $t -notin 'ListItem', 'List', 'Hyperlink', 'Text') { $rows += [pscustomobject]$combo; $combo = $null }
    if ($t -eq 'Text' -and $n) { if (-not $combo) { $label = $n }; continue }
    if ($t -in 'Slider', 'Spinner') {
      $rp = $null; $row = [ordered]@{ label = $label; control = $t }
      if ($e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rp)) { $row.min = $rp.Current.Minimum; $row.max = $rp.Current.Maximum; $row.value = $rp.Current.Value }
      $rows += [pscustomobject]$row
    } elseif ($t -eq 'CheckBox') {
      $tp = $null; $st = if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$tp)) { "$($tp.Current.ToggleState)" } else { '?' }
      $rows += [pscustomobject][ordered]@{ label = $label; control = 'CheckBox'; value = $st }
    } elseif ($t -eq 'Button' -and $n -and $n -notin 'Apply', 'Documentation', 'OK', 'Cancel') {
      $combo = [ordered]@{ label = $label; control = 'Combo'; value = $n; options = @() }
    } elseif ($t -eq 'ListItem' -and $combo -and $n) { $combo.options += $n }
  }
  if ($combo) { $rows += [pscustomobject]$combo }
  $rows
}

Invoke-El (Plus) | Out-Null; Start-Sleep 2
$names = @(Dialog-Tiles | % { ([string]$_.Current.Name).Trim() })
Invoke-El (Find-ByName (Get-EditorDoc) 'Cancel' 'Button') | Out-Null; Start-Sleep 1
"== $Category : $($names.Count) items"
$result = [ordered]@{}; $k = 0
foreach ($name in $names) {
  if ($Only -and $Only -notcontains $name) { continue }
  if ($k++ -ge $Limit) { break }
  Invoke-El (Plus) | Out-Null; Start-Sleep 2
  $tile = Dialog-Tiles | ? { ([string]$_.Current.Name).Trim() -eq $name } | Select -First 1
  Invoke-El ($walker.GetParent($tile)) | Out-Null; Start-Sleep 1
  Invoke-El (Find-ByName (Get-EditorDoc) 'OK' 'Button') | Out-Null; Start-Sleep 2
  $r = Cat-Range; $L = $r[0]; $items = @($L[($r[1] + 2)..($r[2] - 1)])
  $item = $items | ? { (& $ascii $_.Current.Name) -eq $name } | Select -Last 1  # newest is last
  if (-not $item) { "  $name : not added - stopping"; break }
  Invoke-El $item | Out-Null; Start-Sleep 2           # select -> shows its panel
  $panel = Read-PanelV3 $name
  $result[$name] = $panel
  $result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out $OutFile)
  # remove: the icon-only link right after the (selected) item
  $r = Cat-Range; $L = $r[0]; $x = $null
  for ($i = $r[1] + 2; $i -lt $r[2]; $i++) { if ((& $ascii $L[$i].Current.Name) -eq $name -and $i + 1 -lt $r[2] -and -not (& $ascii $L[$i + 1].Current.Name)) { $x = $L[$i + 1] } }
  if ($x) { Invoke-El $x | Out-Null; Start-Sleep 2 } else { "  $name : remove button not found - stopping"; break }
  $left = (Cat-Range); "  {0,-40} {1,2} controls; {2} left in category" -f $name, @($panel).Count, ($left[2] - $left[1] - 2)
}
"done"


