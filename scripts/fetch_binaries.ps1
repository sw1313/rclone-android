# Downloads official rclone Android 21 binaries and fusermount helpers
# into android/app/src/main/jniLibs/<abi>/ as librclone.so / libfusermount.so.
# Android 10+ cannot execute files copied into the app data directory.
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Jni = Join-Path $Root "android\app\src\main\jniLibs"
$Tmp = Join-Path $Root ".bin-cache"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

function Expand-Gz([string]$InFile, [string]$OutFile) {
    $inStream = [System.IO.File]::OpenRead($InFile)
    try {
        $gzip = New-Object System.IO.Compression.GzipStream($inStream, [System.IO.Compression.CompressionMode]::Decompress)
        try {
            $outStream = [System.IO.File]::Create($OutFile)
            try { $gzip.CopyTo($outStream) } finally { $outStream.Close() }
        } finally { $gzip.Close() }
    } finally { $inStream.Close() }
}

function Get-File([string]$Url, [string]$Dest) {
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

$RcloneVersion = "v1.75.0"
$Jobs = @(
    @{
        Abi = "arm64-v8a"
        RcloneUrl = "https://beta.rclone.org/$RcloneVersion/testbuilds/rclone-android-21-armv8a.gz"
        FuseUrl = "https://raw.githubusercontent.com/AvinashReddy3108/rclone-mount-magisk/master/common/binary/arm64/fusermount"
    },
    @{
        Abi = "armeabi-v7a"
        RcloneUrl = "https://beta.rclone.org/$RcloneVersion/testbuilds/rclone-android-21-armv7a.gz"
        FuseUrl = "https://raw.githubusercontent.com/AvinashReddy3108/rclone-mount-magisk/master/common/binary/arm/fusermount"
    },
    @{
        Abi = "x86_64"
        RcloneUrl = "https://beta.rclone.org/$RcloneVersion/testbuilds/rclone-android-21-x64.gz"
        FuseUrl = "https://raw.githubusercontent.com/AvinashReddy3108/rclone-mount-magisk/master/common/binary/x64/fusermount"
    }
)

foreach ($job in $Jobs) {
    $dir = Join-Path $Jni $job.Abi
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -Path (Join-Path $dir ".gitkeep") -Value ""

    $gz = Join-Path $Tmp ("rclone-{0}.gz" -f $job.Abi)
    if (-not (Test-Path $gz)) {
        Get-File $job.RcloneUrl $gz
    }
    $rcloneOut = Join-Path $dir "librclone.so"
    Expand-Gz $gz $rcloneOut
    Write-Host "Wrote $rcloneOut"

    $fuseOut = Join-Path $dir "libfusermount.so"
    Get-File $job.FuseUrl $fuseOut
    Write-Host "Wrote $fuseOut"
}

Set-Content -Path (Join-Path $Jni "VERSION") -Value "rclone $RcloneVersion android-21"
Write-Host "Done. Binaries are in $Jni"
