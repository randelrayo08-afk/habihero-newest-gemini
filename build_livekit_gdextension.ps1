# Build script for the LiveKit GDExtension on Windows
# Usage: .\build_livekit_gdextension.ps1
# Prerequisites:
# - Godot 4.6.1 source or headers available in GODOT_CPP_DIR
# - SCons installed and on PATH
# - Visual Studio / MSVC toolchain available
# - LiveKit C++ SDK headers/libraries available in LIVEKIT_SDK_DIR

param(
    [string]$GodotCppDir = "$env:USERPROFILE\godot-cpp",
    [string]$LiveKitSdkDir = "$env:USERPROFILE\livekit-sdk",
    [string]$OutputDir = "$PSScriptRoot\addons\godot-livekit\bin",
    [string]$BuildDir = "$PSScriptRoot\build",
    [string]$Config = "release"
)

if (-not (Test-Path $GodotCppDir)) {
    Write-Error "Godot C++ bindings directory not found: $GodotCppDir"
    return
}

if (-not (Test-Path $LiveKitSdkDir)) {
    Write-Error "LiveKit SDK directory not found: $LiveKitSdkDir"
    return
}

Write-Host "Building LiveKit GDExtension with Godot C++ bindings from: $GodotCppDir"
Write-Host "LiveKit SDK dir: $LiveKitSdkDir"
Write-Host "Output dir: $OutputDir"

# Ensure output directory exists
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# Build arguments - update include/lib paths as needed
$sconsArgs = @(
    "platform=windows",
    "target=$Config",
    "use_mingw=no",
    "verbose=yes",
    "module_gdextension_enabled=yes",
    "godot_cpp_dir=$GodotCppDir",
    "livekit_sdk_dir=$LiveKitSdkDir",
    "build_dir=$BuildDir"
)

Write-Host "Running SCons..."
$sconsCommand = "scons " + ($sconsArgs -join ' ')
Write-Host $sconsCommand
Invoke-Expression $sconsCommand

Write-Host "Build script complete. If SCons succeeds, copy the generated DLLs into $OutputDir."
