# Structure-aware reader for a WE particle-editor property panel (embedded Chromium, via UI Automation).
# Observed layout (see README): every field = Group(Text label) followed by its controls as siblings:
#   number      -> [Slider] Spinner
#   vector      -> Text 'X' Spinner, Text 'Y' Spinner, Text 'Z' Spinner
#   checkbox    -> small Group (w<40) whose Text is an icon glyph: U+F0C8 unchecked, U+F14A checked
#   combo       -> Button(current value) + List of ListItem options
#   section     -> Group(Text) followed directly by another label Group (no control)
function Read-PanelV3([string]$title) {
  $all = Get-All (Get-EditorDoc); $first = -1
  for ($j = 0; $j -lt $all.Count; $j++) {
    if ($all[$j].Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and ([string]$all[$j].Current.Name).Trim() -eq $title) { $first = $j }
  }
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $rows = New-Object System.Collections.ArrayList
  $section = ''; $label = ''; $axis = $null; $combo = $null; $gotControl = $true
  for ($i = $first + 1; $i -lt $all.Count; $i++) {
    $e = $all[$i]; $c = $e.Current; $t = $c.ControlType.ProgrammaticName.Replace('ControlType.', ''); $raw = [string]$c.Name; $n = $raw.Trim()
    if ($n -eq 'Particle count:') { break }
    $parent = $walker.GetParent($e); $pt = $parent.Current.ControlType.ProgrammaticName
    if ($t -in 'ListItem', 'Hyperlink') { if ($combo -and $t -eq 'ListItem' -and $n) { [void]$combo.options.Add($n) }; continue }
    if ($t -eq 'List') { continue }
    if ($pt -eq 'ControlType.Button') { continue }   # the button's own caption text
    if ($combo) { [void]$rows.Add([pscustomobject]$combo); $combo = $null }
    if ($t -eq 'Group') { continue }
    if ($t -eq 'Text' -and $pt -eq 'ControlType.Group' -and $parent.Current.BoundingRectangle.Width -lt 40) {
      $code = if ($raw.Length) { [int][char]$raw[0] } else { 0 }
      $prevRow = if ($rows.Count) { $rows[$rows.Count - 1] } else { $null }
      if ($code -eq 0xF0C8 -or $code -eq 0xF14A) {
        # each checkbox draws an empty square (F0C8, always) and a ticked square (F14A, only when checked)
        if ($prevRow -and $prevRow.field -eq $label -and $prevRow.type -eq 'bool') { if ($code -eq 0xF14A) { $prevRow.add_default = $true } }
        else { [void]$rows.Add([pscustomobject][ordered]@{ section = $section; field = $label; type = 'bool'; add_default = ($code -eq 0xF14A) }) }
        $gotControl = $true
      }
      continue
    }
    if ($t -eq 'Text' -and $pt -eq 'ControlType.Group' -and $n) {
      if (-not $gotControl -and $label) { $section = $label }   # previous label had no control -> it was a section title
      $label = $n; $axis = $null; $gotControl = $false; continue
    }
    if ($t -eq 'Text' -and $n) { $axis = if ($n -in 'X', 'Y', 'Z', 'W') { $n.ToLower() } else { $n }; continue }   # inline sub-label (X/Y/Z, Width/Depth, ...)
    if ($t -in 'Slider', 'Spinner') {
      $rp = $null; $has = $e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rp)
      $fname = if ($axis) { "$label.$axis" } else { $label }
      $prev = if ($rows.Count) { $rows[$rows.Count - 1] } else { $null }
      if ($t -eq 'Spinner' -and $prev -and $prev.field -eq $fname -and $prev.control -eq 'slider') { $axis = $null; continue }  # value box paired with slider
      $row = [ordered]@{ section = $section; field = $fname; type = 'number'; control = $t.ToLower() }
      if ($has) {
        if ($t -eq 'Slider') { $row.slider_min = $rp.Current.Minimum; $row.slider_max = $rp.Current.Maximum }
        $row.add_default = $rp.Current.Value
      }
      [void]$rows.Add([pscustomobject]$row); $gotControl = $true; $axis = $null; continue
    }
    if ($t -eq 'Button' -and $n -and $n -notin 'Apply', 'Documentation', 'OK', 'Cancel', 'Browse', 'Reset', 'Copy', 'Paste') {
      $combo = [ordered]@{ section = $section; field = $label; type = 'combo'; add_default = $n; options = (New-Object System.Collections.ArrayList) }
      $gotControl = $true; continue
    }
  }
  if ($combo) { [void]$rows.Add([pscustomobject]$combo) }
  $rows.ToArray()
}




