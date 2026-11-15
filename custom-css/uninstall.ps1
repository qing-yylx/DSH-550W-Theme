<#
  uninstall.ps1 —— 把「自定义 CSS」插件从 DSH 的 profile 里移除

  用法：右键这个文件 → 「使用 PowerShell 运行」，或者
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1

  只会撤销安装时做的改动，不会删除这个插件文件夹本身，扔掉即可。
  如果安装时留过 package.json.custom-css-backup，可以手动把它换回去。
#>
[CmdletBinding()]
param(
  [string]$ProfileName = 'desktop',
  [string]$DshHome,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$bundleName = '@local/custom-css'
$entryId = 'custom-css'

function Fail([string]$message) { Write-Host "[错误] $message" -ForegroundColor Red; exit 1 }
function Info([string]$message) { Write-Host "[信息] $message" -ForegroundColor Cyan }
function Ok([string]$message) { Write-Host "[完成] $message" -ForegroundColor Green }
function Plan([string]$message) { Write-Host "[预览] $message" -ForegroundColor Yellow }

$explicitHome = [bool]$DshHome
if (-not $DshHome) {
  if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME } else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
$profilesRoot = Join-Path $DshHome 'profiles'
if (-not (Test-Path -LiteralPath $profilesRoot)) { Fail "没找到 DSH 的配置目录：$profilesRoot" }

$profileDir = $null
if ((-not $explicitHome) -and $env:DSH_PROFILE_DIR -and (Test-Path -LiteralPath $env:DSH_PROFILE_DIR)) {
  $profileDir = $env:DSH_PROFILE_DIR
} elseif (Test-Path -LiteralPath (Join-Path $profilesRoot $ProfileName)) {
  $profileDir = Join-Path $profilesRoot $ProfileName
} else {
  $candidates = @(Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'package.json') })
  if ($candidates.Count -eq 1) { $profileDir = $candidates[0].FullName }
  else { Fail '请用 -ProfileName 指定要卸载的 profile。' }
}

Info "profile：$profileDir"

# 1) package.json：去掉依赖与 bundle
$packagePath = Join-Path $profileDir 'package.json'
$packageText = [System.IO.File]::ReadAllText($packagePath, [System.Text.Encoding]::UTF8)
$package = $packageText | ConvertFrom-Json

if ($package.PSObject.Properties['dependencies'] -and $package.dependencies.PSObject.Properties[$bundleName]) {
  if ($DryRun) { Plan "从 dependencies 移除 $bundleName" }
  else {
    $package.dependencies.PSObject.Properties.Remove($bundleName)
    Info "已移除依赖"
  }
}
if ($package.PSObject.Properties['dsh'] -and $package.dsh.PSObject.Properties['profile']) {
  $profileSection = $package.dsh.profile
  if ($profileSection.PSObject.Properties['bundles'] -and $profileSection.bundles) {
    $kept = @($profileSection.bundles | Where-Object { $_ -ne $bundleName })
    if ($kept.Count -ne @($profileSection.bundles).Count) {
      if ($DryRun) { Plan "从 dsh.profile.bundles 移除 $bundleName" }
      else {
        $profileSection | Add-Member -NotePropertyName 'bundles' -NotePropertyValue $kept -Force
        Info "已从 bundle 列表移除"
      }
    }
  }
}
if (-not $DryRun) {
  [System.IO.File]::WriteAllText($packagePath, ($package | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
  Info "已更新 profile 的 package.json"
}

# 2) 删掉 Junction
$linkPath = Join-Path $profileDir 'node_modules\@local\custom-css'
if (Test-Path -LiteralPath $linkPath) {
  $item = Get-Item -LiteralPath $linkPath -Force
  if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    if ($DryRun) { Plan "删除 Junction：$linkPath" }
    else { cmd /c rmdir "$linkPath" | Out-Null; Info "已删除链接" }
  } else {
    Info "node_modules 里的 custom-css 不是链接，跳过（不动你的文件）"
  }
}

# 3) cordis.patch.yml：删掉那两行条目
$patchPath = Join-Path $profileDir 'cordis.patch.yml'
if (Test-Path -LiteralPath $patchPath) {
  $lines = [System.IO.File]::ReadAllLines($patchPath, [System.Text.Encoding]::UTF8)
  $kept = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match "^\s*-\s*id:\s*$([regex]::Escape($entryId))\s*$") {
      if ($i + 1 -lt $lines.Length -and $lines[$i + 1] -match 'name:\s*["'']@local/custom-css["'']') { $i++ }
      continue
    }
    $kept.Add($lines[$i])
  }
  if ($kept.Count -ne $lines.Length) {
    if ($DryRun) { Plan "从 cordis.patch.yml 删除 $entryId 条目" }
    else {
      [System.IO.File]::WriteAllText($patchPath, (($kept -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
      Info "已更新 cordis.patch.yml"
    }
  }
}

Write-Host ''
if ($DryRun) { Ok '预览结束，没有写入任何文件。' }
else {
  Ok '卸载完成，重新打开 DSH 即恢复默认外观。'
  Write-Host '插件文件夹可以直接删掉。' -ForegroundColor White
}
