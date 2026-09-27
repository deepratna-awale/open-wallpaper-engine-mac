# Remap value: set Input/Output combos, read the conditional fields (e.g. input component), for each combination.
. (Join-Path $PSScriptRoot 'uia.ps1'); . (Join-Path $PSScriptRoot 'panel_reader.ps1')
$asc = { param($x) (([string]$x) -replace '[^\x20-\x7e]', '').Trim() }
$w = [System.Windows.Automation.TreeWalker]::ControlViewWalker
function LL { @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' }) }
function Set-Combo([string]$label, [string]$option) {
  # the combo button follows its label; its options are the hyperlinks inside the List right after it
  $all = Get-All (Get-EditorDoc); $seen = $false; $btn = $null
  for ($i = 0; $i -lt $all.Count; $i++) {
    $e = $all[$i]; $n = ([string]$e.Current.Name).Trim(); $t = $e.Current.ControlType.ProgrammaticName
    if ($t -eq 'ControlType.Text' -and $n -eq $label) { $seen = $true; continue }
    if ($seen -and $t -eq 'ControlType.Button') { $btn = $e; $start = $i; break }
  }
  Invoke-El $btn | Out-Null; Start-Sleep 1
  $all = Get-All (Get-EditorDoc)
  for ($i = $start; $i -lt [math]::Min($all.Count, $start + 60); $i++) {
    if ($all[$i].Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' -and ([string]$all[$i].Current.Name).Trim() -eq $option) { Invoke-El $all[$i] | Out-Null; Start-Sleep 1; return $true }
  }
  return $false
}
foreach ($cat in @(@('Operators', 'Remap value'), @('Initializers', 'Remap initial value'))) {
  $Category = $cat[0]; $Name = $cat[1]
  $L = LL; for ($i = 0; $i -lt $L.Count; $i++) { if ((& $asc $L[$i].Current.Name) -eq $Category) { Invoke-El $L[$i + 1] | Out-Null; break } }; Start-Sleep 2
  $tile = @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and ([string]$_.Current.Name).Trim() -eq $Name })[-1]
  Invoke-El ($w.GetParent($tile)) | Out-Null; Start-Sleep 1; Invoke-El (Find-ByName (Get-EditorDoc) 'OK' 'Button') | Out-Null; Start-Sleep 2
  Invoke-El (LL | ? { (& $asc $_.Current.Name) -eq $Name } | Select -Last 1) | Out-Null; Start-Sleep 2
  foreach ($combo in @(@('Position', 'Position'), @('Position', 'Size'), @('Velocity', 'Color'), @('Color', 'Opacity'))) {
    $okIn = Set-Combo 'Input' $combo[0]; $okOut = Set-Combo 'Output' $combo[1]; Start-Sleep 1
    "== $Name  Input=$($combo[0]) ($okIn)  Output=$($combo[1]) ($okOut)"
    Read-PanelV3 $Name | ? { $_.type -eq 'combo' -or $_.type -eq 'bool' } | % { "   {0,-26} {1,-6} = {2,-16} {3}" -f $_.field, $_.type, $_.add_default, $(if ($_.options) { $_.options -join '/' }) }
  }
  $L = LL; $x = $null; for ($i = 0; $i -lt $L.Count - 1; $i++) { if ((& $asc $L[$i].Current.Name) -eq $Name -and -not (& $asc $L[$i + 1].Current.Name)) { $x = $L[$i + 1] } }
  if ($x) { Invoke-El $x | Out-Null; Start-Sleep 1; "(removed $Name)" } else { "WARNING: $Name not removed" }
}

