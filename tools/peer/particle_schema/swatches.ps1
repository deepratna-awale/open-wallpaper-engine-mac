# Adds a component, samples the on-screen colour of each colour-picker swatch (class sp-replacer) next to its label, removes it.
param([string]$Category, [string]$Name)
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName System.Drawing
$asc = { param($x) (([string]$x) -replace '[^\x20-\x7e]', '').Trim() }
$w = [System.Windows.Automation.TreeWalker]::ControlViewWalker
function LL { @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' }) }
$L = LL; for ($i = 0; $i -lt $L.Count; $i++) { if ((& $asc $L[$i].Current.Name) -eq $Category) { Invoke-El $L[$i + 1] | Out-Null; break } }; Start-Sleep 2
$tile = @(Get-All (Get-EditorDoc) | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and ([string]$_.Current.Name).Trim() -eq $Name })[-1]
Invoke-El ($w.GetParent($tile)) | Out-Null; Start-Sleep 1
Invoke-El (Find-ByName (Get-EditorDoc) 'OK' 'Button') | Out-Null; Start-Sleep 2
Invoke-El (LL | ? { (& $asc $_.Current.Name) -eq $Name } | Select -Last 1) | Out-Null; Start-Sleep 2

$all = Get-All (Get-EditorDoc); $first = -1
for ($j = 0; $j -lt $all.Count; $j++) { if ($all[$j].Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and ([string]$all[$j].Current.Name).Trim() -eq $Name) { $first = $j } }
$label = ''
for ($i = $first + 1; $i -lt $all.Count; $i++) {
  $e = $all[$i]; $c = $e.Current; $n = ([string]$c.Name).Trim()
  if ($n -eq 'Particle count:') { break }
  if ($c.ControlType.ProgrammaticName -eq 'ControlType.Text' -and $n -and $n -notmatch '[^\x20-\x7e]') { $label = $n }
  if ($c.ClassName -like 'sp-replacer*') {
    $r = $c.BoundingRectangle
    $bmp = New-Object System.Drawing.Bitmap ([int]$r.Width), ([int]$r.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size); $g.Dispose()
    $px = $bmp.GetPixel([int]($r.Width * 0.3), [int]($r.Height / 2)); $bmp.Dispose()
    "{0,-16} swatch rgb=({1},{2},{3})  normalized=({4:N3} {5:N3} {6:N3})" -f $label, $px.R, $px.G, $px.B, ($px.R / 255), ($px.G / 255), ($px.B / 255)
  }
}
$L = LL; for ($i = 0; $i -lt $L.Count - 1; $i++) { if ((& $asc $L[$i].Current.Name) -eq $Name -and -not (& $asc $L[$i + 1].Current.Name)) { $x = $L[$i + 1] } }
if ($x) { Invoke-El $x | Out-Null; Start-Sleep 1 } else { "WARNING: $Name not removed" }
