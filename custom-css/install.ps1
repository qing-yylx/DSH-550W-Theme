<#
  install.ps1 —— 把「自定义 CSS」插件装进 DSH 的 profile

  用法（普通用户）：
    右键这个文件 → 「使用 PowerShell 运行」
  如果被系统策略拦住，打开 PowerShell，进入这个文件夹后执行：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

  可选参数：
    -ProfileName desktop   指定 profile 名（默认 desktop，找不到会自动挑唯一的一个）
    -DshHome <目录>        指定 DSH 配置目录（默认 %USERPROFILE%\.dsh）
    -DryRun                只打印将要做的改动，不写任何文件

  装完请完全退出 DSH 再重新打开。
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

function Fail([string]$message) {
  Write-Host "[错误] $message" -ForegroundColor Red
  exit 1
}
function Info([string]$message) { Write-Host "[信息] $message" -ForegroundColor Cyan }
function Ok([string]$message) { Write-Host "[完成] $message" -ForegroundColor Green }
function Plan([string]$message) { Write-Host "[预览] $message" -ForegroundColor Yellow }

$pluginDir = (Resolve-Path -LiteralPath (Split-Path -Parent $MyInvocation.MyCommand.Path)).Path
if (-not (Test-Path -LiteralPath (Join-Path $pluginDir 'package.json'))) {
  Fail "请把 install.ps1 放在插件文件夹里一起运行（当前目录：$pluginDir）"
}

$explicitHome = [bool]$DshHome
if (-not $DshHome) {
  if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME } else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
$profilesRoot = Join-Path $DshHome 'profiles'
if (-not (Test-Path -LiteralPath $profilesRoot)) {
  Fail "没找到 DSH 的配置目录：$profilesRoot`n请先打开一次 DSH 桌面版，或确认它装在当前用户下。"
}

$profileDir = $null
if ((-not $explicitHome) -and $env:DSH_PROFILE_DIR -and (Test-Path -LiteralPath $env:DSH_PROFILE_DIR)) {
  $profileDir = $env:DSH_PROFILE_DIR
} elseif (Test-Path -LiteralPath (Join-Path $profilesRoot $ProfileName)) {
  $profileDir = Join-Path $profilesRoot $ProfileName
} else {
  $candidates = @(Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'package.json') })
  if ($candidates.Count -eq 1) {
    $profileDir = $candidates[0].FullName
  } elseif ($candidates.Count -eq 0) {
    Fail "在 $profilesRoot 下没有找到任何 profile，请先运行一次 DSH 桌面版。"
  } else {
    Fail ("找到多个 profile，请用 -ProfileName 指定一个：" + (($candidates | ForEach-Object { $_.Name }) -join '、'))
  }
}

Info "插件目录：$pluginDir"
Info "profile ：$profileDir"
if ($DryRun) { Plan '这是预览模式（-DryRun），不会修改任何文件。' }

$packagePath = Join-Path $profileDir 'package.json'
$packageText = [System.IO.File]::ReadAllText($packagePath, [System.Text.Encoding]::UTF8)
$package = $packageText | ConvertFrom-Json

function Get-Section($parent, [string]$name) {
  $prop = $parent.PSObject.Properties[$name]
  if ($null -eq $prop -or $null -eq $prop.Value) {
    $fresh = New-Object psobject
    $parent | Add-Member -NotePropertyName $name -NotePropertyValue $fresh -Force
    return $fresh
  }
  return $prop.Value
}

# 1) 依赖：link: 指向插件目录
$linkTarget = 'link:' + ($pluginDir -replace '\\', '/')
$dependencies = Get-Section $package 'dependencies'
if ($DryRun) { Plan "dependencies['$bundleName'] = $linkTarget" } else {
  $dependencies | Add-Member -NotePropertyName $bundleName -NotePropertyValue $linkTarget -Force
  Info "已写入依赖：$bundleName -> $linkTarget"
}

# 2) dsh.profile.bundles 里登记这个 bundle
$dshSection = Get-Section $package 'dsh'
$profileSection = Get-Section $dshSection 'profile'
$bundles = @()
if ($profileSection.PSObject.Properties['bundles'] -and $profileSection.bundles) {
  $bundles = @($profileSection.bundles)
}
if ($bundles -notcontains $bundleName) {
  $bundles = @($bundles) + $bundleName
  if ($DryRun) { Plan "dsh.profile.bundles += $bundleName" } else {
    $profileSection | Add-Member -NotePropertyName 'bundles' -NotePropertyValue $bundles -Force
    Info "已登记 bundle：$bundleName"
  }
} else {
  Info "bundle 已在列表里，跳过。"
}

# 3) 写回 package.json（第一次改动前留一份备份）
if (-not $DryRun) {
  $backupPath = $packagePath + '.custom-css-backup'
  if (-not (Test-Path -LiteralPath $backupPath)) {
    [System.IO.File]::WriteAllText($backupPath, $packageText, (New-Object System.Text.UTF8Encoding($false)))
    Info "已备份原 package.json：$backupPath"
  }
  $json = $package | ConvertTo-Json -Depth 32
  [System.IO.File]::WriteAllText($packagePath, $json, (New-Object System.Text.UTF8Encoding($false)))
  Info "已更新 profile 的 package.json"
}

# 4) node_modules 里建 Junction，让 profile 能 require 到插件
$modulesLocal = Join-Path $profileDir 'node_modules\@local'
$linkPath = Join-Path $modulesLocal 'custom-css'
if ($DryRun) {
  Plan "创建目录 $modulesLocal"
  Plan "创建 Junction：$linkPath -> $pluginDir"
} else {
  New-Item -ItemType Directory -Path $modulesLocal -Force | Out-Null
  if (Test-Path -LiteralPath $linkPath) {
    $existing = Get-Item -LiteralPath $linkPath -Force
    $isLink = ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isLink) {
      cmd /c rmdir "$linkPath" | Out-Null
      Info "已移除旧的 Junction"
    } else {
      Fail "目标位置已存在且不是链接：$linkPath`n请先手动移走它再运行。"
    }
  }
  New-Item -ItemType Junction -Path $linkPath -Target $pluginDir | Out-Null
  Ok "已创建链接：$linkPath"
}

# 5) cordis.patch.yml 里确保有这条插件条目
$patchPath = Join-Path $profileDir 'cordis.patch.yml'
$patchText = ''
if (Test-Path -LiteralPath $patchPath) {
  $patchText = [System.IO.File]::ReadAllText($patchPath, [System.Text.Encoding]::UTF8)
}
if ($patchText -match "(?m)^\s*-\s*id:\s*$([regex]::Escape($entryId))\s*$") {
  Info "cordis.patch.yml 里已有 $entryId，跳过。"
} else {
  $block = "- id: $entryId`r`n  name: '$bundleName'"
  if ($DryRun) {
    Plan "向 cordis.patch.yml 追加：$($block -replace "`r`n", ' / ')"
  } else {
    if ($patchText -and -not $patchText.EndsWith("`n")) { $patchText += "`r`n" }
    $patchText += $block + "`r`n"
    [System.IO.File]::WriteAllText($patchPath, $patchText, (New-Object System.Text.UTF8Encoding($false)))
    Info "已更新 cordis.patch.yml"
  }
}

Write-Host ''
if ($DryRun) {
  Ok '预览结束，没有写入任何文件。去掉 -DryRun 就会真正安装。'
} else {
  Ok '安装完成。'
  Write-Host '接下来：' -ForegroundColor White
  Write-Host '  1. 完全退出 DSH 桌面版（托盘图标也要退），再打开；'
  Write-Host '  2. 打开 设置 → 插件，确认「自定义 CSS」是开启状态；'
  Write-Host '  3. 窗口背景应该已经变成 550W 壁纸。'
}
