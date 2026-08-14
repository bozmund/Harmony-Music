<#
.SYNOPSIS
  Runs `flutter run` on a dynamically-selected device, for use from Zed tasks
  (.zed/tasks.json). Avoids hardcoding a specific device id/name so the same
  task keeps working across reconnects and across different phones.

.PARAMETER Platform
  Which connected device to target: windows, chrome, or android. For
  "android", the currently connected Android device is looked up by its
  reported targetPlatform (android-arm64, android-arm, ...) rather than a
  fixed name/id, since those change per phone and per (re)connection.

.PARAMETER Mode
  Build mode to pass to `flutter run`: debug, profile, or release.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("windows", "chrome", "android")]
    [string]$Platform,

    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "debug"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $repoRoot ".flutter\bin\flutter.bat"

$devicesJson = & $flutter devices --machine | Out-String
$devices = $devicesJson | ConvertFrom-Json

$matches = switch ($Platform) {
    "windows" { $devices | Where-Object { $_.targetPlatform -eq "windows-x64" } }
    "chrome" { $devices | Where-Object { $_.targetPlatform -eq "web-javascript" } }
    "android" { $devices | Where-Object { $_.targetPlatform -like "android-*" } }
}

if (-not $matches -or @($matches).Count -eq 0) {
    Write-Host "No connected '$Platform' device found. Currently visible devices:"
    & $flutter devices
    exit 1
}

if (@($matches).Count -gt 1) {
    Write-Host "Multiple '$Platform' devices are connected - pick one explicitly:"
    foreach ($d in $matches) {
        Write-Host "  $($d.name)  [$($d.id)]"
    }
    Write-Host "Run: flutter run --target lib/main.dart -d <id> --$Mode"
    exit 1
}

$device = @($matches)[0]
Write-Host "Using device: $($device.name) [$($device.id)]"

if ($Platform -eq "android") {
    # This project's Gradle wrapper (8.14.3) can't run under JDK 25+:
    # https://github.com/gradle/gradle/issues/35111 (fixed in Gradle 9.1.0). If
    # JAVA_HOME isn't already pointing at a working JDK, look for a compatible one
    # (17-24) under the usual Windows install root and use it just for this run,
    # instead of touching global Flutter/Android Studio JDK settings or committing
    # a machine-specific path into the repo.
    $javaRoot = "C:\Program Files\Java"
    $compatibleJdk = $null
    if (Test-Path $javaRoot) {
        $compatibleJdk = Get-ChildItem $javaRoot -Directory |
            Where-Object { $_.Name -match '^jdk-(\d+)' -and (Test-Path (Join-Path $_.FullName "bin\java.exe")) } |
            ForEach-Object { [PSCustomObject]@{ Path = $_.FullName; Major = [int]$Matches[1] } } |
            Where-Object { $_.Major -ge 17 -and $_.Major -le 24 } |
            Sort-Object Major -Descending |
            Select-Object -First 1 -ExpandProperty Path
    }

    if ($compatibleJdk) {
        Write-Host "Using JDK for Gradle: $compatibleJdk (Gradle 8.14.3 doesn't support JDK 25+ yet)"
        # JAVA_HOME alone is not enough, and silently so: Flutter picks the JDK it
        # hands to Gradle in the order `flutter config --jdk-dir` > Android Studio's
        # bundled JBR > JAVA_HOME > PATH. With Android Studio installed, its JBR
        # wins and JAVA_HOME is never consulted — so this script printed the line
        # above and the build still died on the JBR's version string.
        #
        # org.gradle.java.home is read by Gradle itself, after Flutter has already
        # handed off, so it overrides that choice without touching global Flutter
        # config or committing a machine-specific path into android/gradle.properties.
        # The inner quotes matter: GRADLE_OPTS is split on whitespace, and this path
        # contains a space ("Program Files").
        $env:JAVA_HOME = $compatibleJdk
        $gradleJdkOption = "-Dorg.gradle.java.home=`"$compatibleJdk`""
        $env:GRADLE_OPTS = if ($env:GRADLE_OPTS) { "$env:GRADLE_OPTS $gradleJdkOption" } else { $gradleJdkOption }
    }
    else {
        Write-Host "Warning: no Gradle-compatible JDK (17-24) found under '$javaRoot'."
        Write-Host "The Android Gradle build will likely fail if the default JDK is 25+. Install a JDK 17 or 21, or upgrade this project's Gradle wrapper to 9.1.0+."
    }
}

& $flutter run --target lib/main.dart -d $device.id "--$Mode"
exit $LASTEXITCODE
