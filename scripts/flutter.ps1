param([Parameter(ValueFromRemainingArguments=$true)][string[]]$FlutterArguments)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$localSdk = Join-Path (Split-Path $projectRoot -Parent) '.flutter-sdk\bin\flutter.bat'
$command = Get-Command flutter -ErrorAction SilentlyContinue
if ($command) { $flutterCommand = $command.Source } elseif (Test-Path -LiteralPath $localSdk) { $flutterCommand = $localSdk } else { throw '请安装 Flutter stable 并加入 PATH' }
Set-Location $projectRoot
$taskCache = Join-Path $projectRoot '.cache'
New-Item -ItemType Directory -Force -Path "$taskCache\tmp","$taskCache\gradle" | Out-Null
$env:GRADLE_USER_HOME = "$taskCache\gradle"
$env:PUB_CACHE = "$taskCache\pub"
$env:TEMP = "$taskCache\tmp"
$env:TMP = $env:TEMP
& $flutterCommand @FlutterArguments
exit $LASTEXITCODE
