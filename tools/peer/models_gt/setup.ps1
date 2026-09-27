# Copies the generated MG projects into WE's myprojects and builds the variant projects (MG2 local copy, MG6/MG8 collisionmodel variants).
$ErrorActionPreference = 'Stop'
$we = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
$my = "$we\projects\myprojects"
$ws = "C:\Program Files (x86)\Steam\steamapps\workshop\content\431960"
$req = Join-Path $PSScriptRoot "..\requests\models-gt"

# generated projects (prefix mg_ so cleanup is easy)
Get-ChildItem $req -Directory -Filter 'gt-*' | % { $d = "$my\mg_$($_.Name)"; if (Test-Path $d) { Remove-Item $d -Recurse -Force }; Copy-Item $_.FullName $d -Recurse }

# MG2: local copies of the Solar system, as shipped and with transparentsorting false (loose scene.json next to scene.pkg)
foreach ($v in 'shipped', 'nosort') {
  $d = "$my\mg_solar_$v"; if (Test-Path $d) { Remove-Item $d -Recurse -Force }
  Copy-Item "$ws\3455121165" $d -Recurse
  $scene = & (Join-Path $PSScriptRoot '..\pkg.ps1') "$d\scene.pkg" 'scene.json'
  if ($v -eq 'nosort') { $scene = [regex]::Replace($scene, '("transparentsorting"\s*:\s*)true', '${1}false') }
  [IO.File]::WriteAllText("$d\scene.json", $scene)
  "mg_solar_$v transparentsorting: " + [regex]::Match($scene, '"transparentsorting"\s*:\s*\w+').Value
}

# MG6/MG8: collisionmodel element preview with particle depthtest on/off and the sphere hidden
$src = "$we\assets\scenes\particleelementpreviews\collisionmodel"
foreach ($v in 'shipped', 'depthon', 'depthoff', 'spherehidden') {
  $d = "$my\mg_colmodel_$v"; if (Test-Path $d) { Remove-Item $d -Recurse -Force }; Copy-Item $src $d -Recurse
  if (-not (Test-Path "$d\project.json")) { [IO.File]::WriteAllText("$d\project.json", '{"file":"scene.json","title":"mg_colmodel_' + $v + '","type":"scene","general":{"properties":{}}}') }
  $scene = [IO.File]::ReadAllText("$d\scene.json")
  if ($v -like 'depth*') {
    $mat = Get-ChildItem "$d\materials" -Recurse -Filter *.json | ? { (Get-Content $_.FullName -Raw) -match 'genericparticle' } | Select -First 1
    if ($mat) { $m = Get-Content $mat.FullName -Raw; $val = if ($v -eq 'depthon') { 'enabled' } else { 'disabled' }; $m = [regex]::Replace($m, '("depthtest"\s*:\s*)"\w+"', "`${1}`"$val`""); [IO.File]::WriteAllText($mat.FullName, $m); "mg_colmodel_$v particle material $($mat.Name): depthtest=$val" }
  }
  if ($v -eq 'spherehidden') {
    $j = $scene | ConvertFrom-Json
    $models = @($j.objects | ? { $_.model -or ($_.image -and $_.image -notlike '*solidlayer*' -and -not $_.particle) })
    "collisionmodel objects: " + (($j.objects | % { "$($_.name)[$(if($_.particle){'particle'}elseif($_.model){'model'}elseif($_.image){'image'}else{'other'})]" }) -join ', ')
    foreach ($o in $j.objects) { if ($o.model -or ($o.name -match '(?i)sphere')) { $o | Add-Member -NotePropertyName visible -NotePropertyValue $false -Force } }
    [IO.File]::WriteAllText("$d\scene.json", ($j | ConvertTo-Json -Depth 30))
  }
}
Get-ChildItem $my -Directory -Filter 'mg_*' | % Name
