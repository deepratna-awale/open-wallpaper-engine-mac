# Adds one component to a category, dumps its raw panel (every element with type, name, patterns, values), removes it.
param([string]$Category, [string]$Name, [int]$Max = 80)
. (Join-Path $PSScriptRoot 'uia.ps1')
$asc = { param($x) (([string]$x) -replace '[^\x20-\x7e]', '').Trim() }
$w = [System.Windows.Automation.TreeWalker]::ControlViewWalker
function LL { @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' }) }
function CatIdx { $L = LL; for ($i = 0; $i -lt $L.Count; $i++) { if ((& $asc $L[$i].Current.Name) -eq $Category) { return , @($L, $i) } } }

$r = CatIdx; Invoke-El $r[0][$r[1] + 1] | Out-Null; Start-Sleep 2
$tile = @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and ([string]$_.Current.Name).Trim() -eq $Name })[-1]
Invoke-El ($w.GetParent($tile)) | Out-Null; Start-Sleep 1
Invoke-El (Find-ByName (Get-EditorDoc) 'OK' 'Button') | Out-Null; Start-Sleep 2
$item = LL | ? { (& $asc $_.Current.Name) -eq $Name } | Select -Last 1
Invoke-El $item | Out-Null; Start-Sleep 2

$all = Get-All (Get-EditorDoc); $first = -1
for ($j = 0; $j -lt $all.Count; $j++) { if ($all[$j].Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and ([string]$all[$j].Current.Name).Trim() -eq $Name) { $first = $j } }
"== $Name (raw panel)"
for ($i = $first; $i -lt [math]::Min($all.Count, $first + $Max); $i++) {
  $e = $all[$i]; $c = $e.Current; $n = ([string]$c.Name) -replace '[^\x20-\x7e]', { 'U+{0:X4}' -f [int][char]$_.Value }
  if ($n -eq 'Particle count:') { break }
  $pats = ($e.GetSupportedPatterns() | % { $_.ProgrammaticName -replace 'PatternIdentifiers.Pattern', '' }) -join ','
  $val = ''; $vp = $null; $rp = $null
  if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { $val = "value='$($vp.Current.Value)'" }
  if ($e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rp)) { $val += " range=$($rp.Current.Minimum)..$($rp.Current.Maximum) v=$($rp.Current.Value)" }
  $h = $c.HelpText; $cls = $c.ClassName
  "{0,3} {1,-9} '{2}' w{3:N0} [{4}] {5} {6} {7}" -f $i, $c.ControlType.ProgrammaticName.Replace('ControlType.', ''), $n, $c.BoundingRectangle.Width, $pats, $val, $(if ($h) { "help='$h'" }), $(if ($cls) { "class=$cls" })
}
# remove it again
$L = LL; for ($i = 0; $i -lt $L.Count - 1; $i++) { if ((& $asc $L[$i].Current.Name) -eq $Name -and -not (& $asc $L[$i + 1].Current.Name)) { $x = $L[$i + 1] } }
if ($x) { Invoke-El $x | Out-Null; Start-Sleep 1; "(removed)" } else { "WARNING: not removed" }
