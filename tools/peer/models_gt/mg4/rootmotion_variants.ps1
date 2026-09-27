# Drives WE's Model Editor (Configure Model > clip options) through the root-motion settings and saves the .mdl
# the editor writes for each: root bone None / root with all axes off / each axis alone / all on.
. (Join-Path $PSScriptRoot '..\ed.ps1')
$proj = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects\mg4_rootmotion_i"
$out = Join-Path $PSScriptRoot 'mdl_variants'; New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $PSScriptRoot 'variants.log'; Set-Content $log ''
function L($m) { $m | Tee-Object -FilePath $log -Append }

function Idx($label, $type = 'Text') { $a = All; for ($i = 0; $i -lt $a.Count; $i++) { if ((Clean $a[$i].Current.Name) -eq $label -and $a[$i].Current.ControlType.ProgrammaticName -eq "ControlType.$type") { return , @($a, $i) } }; , @($a, -1) }
function Toggles {
  # six Invoke-groups following the 'Position' and 'Rotation' labels, in X/Y/Z order
  $r = Idx 'Position'; $a = $r[0]; $i = $r[1]; if ($i -lt 0) { return @() }
  $g = @(); for ($k = $i; $k -lt [math]::Min($a.Count, $i + 40) -and $g.Count -lt 6; $k++) {
    $e = $a[$k]; if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Group' -and $e.Current.BoundingRectangle.Width -lt 40) { $g += $e } }
  $g
}
function State($grp) {
  $on = $false
  foreach ($t in $grp.FindAll('Descendants', $UC)) { $n = [string]$t.Current.Name; if ($n.Length -and [int][char]$n[0] -eq 0xF14A) { $on = $true } }
  $on
}
function Set-Axes([bool[]]$want) {
  for ($pass = 0; $pass -lt 2; $pass++) {
    $g = Toggles
    for ($k = 0; $k -lt 6; $k++) { if ((State $g[$k]) -ne $want[$k]) { Inv $g[$k] | Out-Null; Start-Sleep -Milliseconds 600; $g = Toggles } }
  }
  (Toggles | % { if (State $_) { '1' } else { '0' } }) -join ''
}
function Open-Clip {
  if ((Idx 'Clip options')[1] -lt 0) { Inv (Find 'Configure Model' 'Button') | Out-Null; Start-Sleep 4 }
  $clip = All | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' -and (Clean $_.Current.Name) -like 'Scene (Clip*' } | select -First 1
  if ($clip) { Inv $clip | Out-Null; Start-Sleep 2 }
}
function Set-RootBone($name) {
  $r = Idx 'Motion root bone'; $a = $r[0]; $i = $r[1]
  Inv $a[$i + 1] | Out-Null; Start-Sleep 1
  $a = All; $h = $a[$i..($i + 14)] | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' -and (Clean $_.Current.Name) -eq $name } | select -First 1
  Inv $h | Out-Null; Start-Sleep 2
}
function Save-As($tag) {
  $ok = All | ? { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' -and (Clean $_.Current.Name) -eq 'OK' -and -not $_.Current.IsOffscreen } | sort { -$_.Current.BoundingRectangle.Y } | select -First 1
  Inv $ok | Out-Null; Start-Sleep 2
  Inv (Find 'Save' 'Button') | Out-Null; Start-Sleep 5
  $m = Get-ChildItem "$proj\models" -Recurse -Filter *.mdl | select -First 1
  Copy-Item $m.FullName (Join-Path $out "rootmotion_$tag.mdl") -Force
  L ("{0,-14} saved {1} ({2} bytes, {3})" -f $tag, $m.Name, $m.Length, $m.LastWriteTime.ToString('HH:mm:ss'))
}

$configs = [ordered]@{
  'bone_none' = $null
  'root_all_off' = @($false, $false, $false, $false, $false, $false)
  'root_posX' = @($true, $false, $false, $false, $false, $false)
  'root_posY' = @($false, $true, $false, $false, $false, $false)
  'root_posZ' = @($false, $false, $true, $false, $false, $false)
  'root_rotX' = @($false, $false, $false, $true, $false, $false)
  'root_rotY' = @($false, $false, $false, $false, $true, $false)
  'root_rotZ' = @($false, $false, $false, $false, $false, $true)
  'root_all_on' = @($true, $true, $true, $true, $true, $true)
}
foreach ($k in $configs.Keys) {
  Open-Clip
  if ($null -eq $configs[$k]) { Set-RootBone 'None'; L "$k : root bone None" }
  else { Set-RootBone 'root'; $s = Set-Axes $configs[$k]; L "$k : axes posXYZ rotXYZ = $s" }
  Save-As $k
}
L 'done'

