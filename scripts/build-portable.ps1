param([string]$NativeBundle, [string]$OutputName = 'NeedTODO-Portable')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$env:TEMP = Join-Path $projectRoot '.cache\tmp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
if ($OutputName -notmatch '^NeedTODO-Portable(?:-[A-Za-z0-9-]+)?$') { throw 'Invalid portable output folder name.' }
$output = Join-Path $projectRoot "release\$OutputName"

if ($NativeBundle) {
    $NativeBundle = (Resolve-Path -LiteralPath $NativeBundle).Path
    # Reuse only a native host built with the exact same Flutter engine.
    # This option is for Dart/resource-only changes, not native plugin changes.
    $config = Get-Content '.dart_tool\package_config.json' -Raw | ConvertFrom-Json
    $sdk = ([uri]$config.flutterRoot).LocalPath
    $engine = Join-Path $sdk 'bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll'
    if ((Get-FileHash $engine).Hash -ne (Get-FileHash (Join-Path $NativeBundle 'flutter_windows.dll')).Hash) {
        throw 'The native bundle uses a different Flutter engine. Build a fresh native bundle first.'
    }
    & "$PSScriptRoot\flutter.ps1" assemble '-dTargetPlatform=windows-x64' '-dBuildMode=release' '-dTargetFile=lib/main.dart' '--output=build/portable-assets' release_bundle_windows-x64_assets
    if ($LASTEXITCODE -ne 0) { throw 'Flutter asset compilation failed.' }
} else {
    & "$PSScriptRoot\flutter.ps1" build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    $NativeBundle = Join-Path $projectRoot 'build\windows\x64\runner\Release'
}

if (Get-Process needtodo -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $output 'needtodo.exe') }) {
    throw 'Close the running portable app before rebuilding it.'
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
Get-ChildItem -LiteralPath $NativeBundle | Copy-Item -Destination $output -Recurse -Force
if ($PSBoundParameters.ContainsKey('NativeBundle') -and $PSBoundParameters.NativeBundle) {
    Copy-Item 'build\portable-assets\windows\app.so' (Join-Path $output 'data\app.so') -Force
    Get-ChildItem 'build\portable-assets\flutter_assets' | Copy-Item -Destination (Join-Path $output 'data\flutter_assets') -Recurse -Force
}

# Include the installed Microsoft runtime DLLs app-locally for no-install use.
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    Copy-Item -LiteralPath (Join-Path $env:WINDIR "System32\$name") -Destination $output -Force
}

# Update the native host's icon from the project's transparent ICO.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PortableIcon {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr BeginUpdateResource(string file, bool delete);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool UpdateResource(IntPtr handle, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool EndUpdateResource(IntPtr handle, bool discard);
    public static void Apply(string exe, string icon) {
        byte[] ico = File.ReadAllBytes(icon);
        int count = BitConverter.ToUInt16(ico, 4);
        byte[] group = new byte[6 + 14 * count];
        Array.Copy(ico, group, 6);
        IntPtr handle = BeginUpdateResource(exe, false);
        if (handle == IntPtr.Zero) throw new Win32Exception();
        try {
            for (int i = 0; i < count; i++) {
                int entry = 6 + 16 * i;
                int length = BitConverter.ToInt32(ico, entry + 8);
                int offset = BitConverter.ToInt32(ico, entry + 12);
                byte[] pixels = new byte[length];
                Array.Copy(ico, offset, pixels, 0, length);
                if (!UpdateResource(handle, (IntPtr)3, (IntPtr)(i + 1), 1033, pixels, (uint)length)) throw new Win32Exception();
                Array.Copy(ico, entry, group, 6 + 14 * i, 12);
                Array.Copy(BitConverter.GetBytes((ushort)(i + 1)), 0, group, 18 + 14 * i, 2);
            }
            if (!UpdateResource(handle, (IntPtr)14, (IntPtr)101, 1033, group, (uint)group.Length)) throw new Win32Exception();
            if (!EndUpdateResource(handle, false)) throw new Win32Exception();
            handle = IntPtr.Zero;
        } finally {
            if (handle != IntPtr.Zero) EndUpdateResource(handle, true);
        }
    }
}
'@
[PortableIcon]::Apply((Join-Path $output 'needtodo.exe'), (Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'))
Set-Content -LiteralPath (Join-Path $output 'portable.flag') -Value 'NeedTODO portable mode' -Encoding utf8
@'
泥土豆 · 便携测试版

解压整个文件夹后，双击 needtodo.exe 即可使用，无需安装。
首次打开直接进入本机模式。数据保存在同目录的 user-data 文件夹。
请保留 exe、DLL 和 data 文件夹的相对位置，不要只复制 exe。
请先关闭已运行的其他泥土豆版本，以免单实例机制切换回旧版。
日程数据和提醒图片随文件夹保留；更换测试版本时可保留 user-data。
'@ | Set-Content -LiteralPath (Join-Path $output '使用说明.txt') -Encoding utf8
$archive = Join-Path $projectRoot 'release\NeedTODO-Portable.zip'
$files = Get-ChildItem -LiteralPath $output | Where-Object Name -ne 'user-data'
Compress-Archive -LiteralPath $files.FullName -DestinationPath $archive -Force
Write-Output "Portable app: $output\needtodo.exe"
Write-Output "Portable archive: $archive"
