[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workspace,

    [ValidateSet("auto", "win-x64", "win-arm64")]
    [string]$Runtime = "auto",

    [switch]$Install
)

$ErrorActionPreference = "Stop"
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillDirectory = Split-Path -Parent $scriptDirectory
$project = Join-Path $skillDirectory "assets/windows-app/SavedToAction.Windows.csproj"
$workspacePath = [System.IO.Path]::GetFullPath($Workspace)
$dataPath = Join-Path $workspacePath "saved-to-action.json"

if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
    throw "请用 -Workspace 指向已经初始化的 Saved to Action 工作目录。"
}

if ($Runtime -eq "auto") {
    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $Runtime = if ($architecture -eq "Arm64") { "win-arm64" } else { "win-x64" }
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "找不到 dotnet。请先安装 .NET 8 SDK。"
}

$pythonExecutable = $null
$pythonPrefix = @()
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCommand) {
    $pythonExecutable = $pythonCommand.Source
}
else {
    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pythonLauncher) {
        $pythonExecutable = $pythonLauncher.Source
        $pythonPrefix = @("-3")
    }
}
if (-not $pythonExecutable) {
    throw "找不到 Python 3。请先安装 Python 3 并确保 python 或 py 命令可用。"
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("saved-to-action-build-" + [Guid]::NewGuid().ToString("N"))
$publishDirectory = Join-Path $temporaryRoot "publish"
$outputDirectory = Join-Path $workspacePath ("dist/windows/" + $Runtime)

try {
    New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null
    dotnet publish $project `
        --configuration Release `
        --runtime $Runtime `
        --self-contained true `
        --output $publishDirectory `
        -p:PublishSingleFile=false
    if ($LASTEXITCODE -ne 0) { throw "Windows App 编译失败。" }

    & $pythonExecutable @pythonPrefix (Join-Path $scriptDirectory "saved_to_action.py") configure-app `
        --workspace $workspacePath `
        --output (Join-Path $publishDirectory "AppConfig.json") | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "无法生成 App 工作区配置。" }

    if (Test-Path -LiteralPath $outputDirectory) {
        Remove-Item -LiteralPath $outputDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Copy-Item -Path (Join-Path $publishDirectory "*") -Destination $outputDirectory -Recurse -Force

    if ($Install) {
        $installDirectory = Join-Path $env:LOCALAPPDATA "Programs/SavedToAction"
        if (Test-Path -LiteralPath $installDirectory) {
            throw "安装目标已经存在：$installDirectory。为避免覆盖现有 App，安装已停止。"
        }
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        Copy-Item -Path (Join-Path $publishDirectory "*") -Destination $installDirectory -Recurse -Force
        $pointerDirectory = Join-Path $env:LOCALAPPDATA "SavedToAction"
        New-Item -ItemType Directory -Path $pointerDirectory -Force | Out-Null
        & $pythonExecutable @pythonPrefix (Join-Path $scriptDirectory "saved_to_action.py") configure-app `
            --workspace $workspacePath `
            --output (Join-Path $pointerDirectory "app.json") | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "无法写入 Windows App 配置指针。" }
        Write-Output (Join-Path $installDirectory "SavedToAction.exe")
    }
    else {
        Write-Output (Join-Path $outputDirectory "SavedToAction.exe")
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
