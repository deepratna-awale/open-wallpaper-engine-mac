# Helpers for driving the WE editor (embedded Chromium) through UI Automation.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$script:UA = [System.Windows.Automation.AutomationElement]
$script:UC = [System.Windows.Automation.Condition]::TrueCondition
$script:UW = [System.Windows.Automation.TreeWalker]::ControlViewWalker
function Clean($s) { (([string]$s) -replace '[^\x20-\x7e]', '').Trim() }
function EdDoc {
  foreach ($w in $UA::RootElement.FindAll('Children', $UC)) {
    if ($w.Current.ClassName -ne 'WPEUI') { continue }
    $d = $w.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)))
    if ($d -and ($d.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::NameProperty, 'Wallpaper Editor'))) -or
                 $d.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::NameProperty, 'Welcome'))))) { return $d }
  }
}
function All { @((EdDoc).FindAll('Descendants', $UC)) }
function Find([string]$name, [string]$type = '', [int]$idx = 0) {
  $h = @(All | ? { (Clean $_.Current.Name) -eq $name -and (-not $type -or $_.Current.ControlType.ProgrammaticName -eq "ControlType.$type") })
  if ($h.Count -gt $idx) { $h[$idx] }
}
function Inv($e) {
  if (-not $e) { return $false }
  $p = $null
  foreach ($pat in [System.Windows.Automation.InvokePattern]::Pattern, [System.Windows.Automation.SelectionItemPattern]::Pattern, [System.Windows.Automation.TogglePattern]::Pattern) {
    if ($e.TryGetCurrentPattern($pat, [ref]$p)) {
      try { if ($pat -eq [System.Windows.Automation.InvokePattern]::Pattern) { $p.Invoke() } elseif ($pat -eq [System.Windows.Automation.SelectionItemPattern]::Pattern) { $p.Select() } else { $p.Toggle() }; return $true } catch {}
    }
  }
  $par = $UW.GetParent($e); if ($par) { return (Inv $par) }
  return $false
}
function Dump([int]$max = 80, [string]$match = '') {
  All | ? { $_.Current.Name -and (-not $match -or (Clean $_.Current.Name) -match $match) } | select -First $max | % { "[{0}] {1}" -f $_.Current.ControlType.ProgrammaticName.Replace('ControlType.', ''), (Clean $_.Current.Name) }
}
