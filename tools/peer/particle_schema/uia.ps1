# UI Automation helpers for the WE editor's embedded Chromium page (read + invoke only; no files are saved).
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$script:A = [System.Windows.Automation.AutomationElement]
$script:CT = [System.Windows.Automation.ControlType]
$script:AnyCond = [System.Windows.Automation.Condition]::TrueCondition

function Get-EditorDoc {
  $root = $A::RootElement
  foreach ($w in $root.FindAll('Children', $AnyCond)) {
    if ($w.Current.ClassName -ne 'WPEUI') { continue }
    $d = $w.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, $CT::Document)))
    if ($d -and $d.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, 'Particle Editor')))) { return $d }
  }
}

function Get-All($doc) { @($doc.FindAll('Descendants', $AnyCond)) }

function Find-ByName($doc, [string]$name, [string]$type = 'Hyperlink', [int]$index = 0) {
  $hits = @(Get-All $doc | ? { $_.Current.ControlType.ProgrammaticName -eq "ControlType.$type" -and $_.Current.Name.Trim() -eq $name })
  if ($hits.Count -gt $index) { $hits[$index] }
}

function Invoke-El($e) {
  $p = $null
  if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return $true }
  if ($e.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $p.Select(); return $true }
  return $false
}

# Reads the currently shown property panel: every labelled slider / spinner / checkbox / combo with its range and value.
function Read-Panel($doc) {
  $label = ''; $out = @()
  foreach ($e in (Get-All $doc)) {
    $c = $e.Current; $t = $c.ControlType.ProgrammaticName.Replace('ControlType.', '')
    if ($t -eq 'Text' -and $c.Name.Trim()) { $label = $c.Name.Trim(); continue }
    $row = [ordered]@{ label = $label; control = $t }
    $rp = $null; $vp = $null; $tp = $null
    if ($t -in 'Slider', 'Spinner') {
      if ($e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rp)) {
        $v = $rp.Current; $row.min = $v.Minimum; $row.max = $v.Maximum; $row.value = $v.Value
      }
      $out += [pscustomobject]$row
    } elseif ($t -eq 'CheckBox') {
      if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$tp)) { $row.value = "$($tp.Current.ToggleState)" }
      $out += [pscustomobject]$row
    } elseif ($t -eq 'Button' -and $label -and $c.Name.Trim()) {
      $row.value = $c.Name.Trim(); $out += [pscustomobject]$row  # dropdown buttons show the current option
    }
  }
  $out
}


