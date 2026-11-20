param([string]$Serial = 'emulator-5580')
$ErrorActionPreference = 'Stop'
if ($Serial -notmatch '^emulator-\d+$') { throw 'This test may only change a disposable emulator.' }
$project = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
$ndk = Join-Path $env:ANDROID_HOME 'ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe'
Set-Location -LiteralPath $project
New-Item -ItemType Directory -Force .tools | Out-Null
& $ndk --target=x86_64-linux-android29 tools/dns-probe.c -o .tools/dns-probe -O2 -Wall -Wextra -Werror
if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed' }
& $adb -s $Serial push .tools/dns-probe /data/local/tmp/zowy-dns-probe
& $adb -s $Serial shell chmod 755 /data/local/tmp/zowy-dns-probe
& $adb -s $Serial shell am force-stop dev.zowy.zowy_adblocker
& $adb -s $Serial shell am force-stop com.android.vpndialogs
& $adb -s $Serial logcat -c
$log = Join-Path $project '.tools\integration.log'
Set-Content -LiteralPath $log -Value ''
$job = Start-Job -ScriptBlock {
    param($projectPath, $logPath, $device)
    Set-Location -LiteralPath $projectPath
    & 'C:\dev\flutter\bin\flutter.bat' test integration_test/vpn_device_test.dart -d $device --reporter expanded --no-uninstall *> $logPath
    $LASTEXITCODE
} -ArgumentList $project, $log, $Serial
$authorized = $false
$probed = $false
$deadline = (Get-Date).AddMinutes(6)
try {
    while ((Get-Date) -lt $deadline -and $job.State -eq 'Running') {
        $content = Get-Content -Raw -LiteralPath $log
        if (!$authorized -and $content -match 'ZOWY_VPN_AUTH_READY') {
            & $adb -s $Serial shell pm grant dev.zowy.zowy_adblocker android.permission.POST_NOTIFICATIONS
            & $adb -s $Serial shell cmd jobscheduler run -f dev.zowy.zowy_adblocker 301
            & $adb -s $Serial shell appops set dev.zowy.zowy_adblocker ACTIVATE_VPN allow
            $authorized = $true
            Write-Output 'Authorized test VPN inside emulator.'
        }
        if (!$probed -and $content -match 'ZOWY_TUN_TEST_READY') {
            $probe = & $adb -s $Serial shell /data/local/tmp/zowy-dns-probe 2>&1
            $probeExit = $LASTEXITCODE
            $probe | Tee-Object -FilePath docs/emulator-dns-probe-results.txt
            if ($probeExit -ne 0) { Get-Content -LiteralPath $log; throw 'Independent DNS probe failed.' }
            $probed = $true
        }
        Start-Sleep -Seconds 1
    }
    Get-Content -LiteralPath $log
    if ($job.State -eq 'Running') { throw 'Integration test timed out.' }
    $exitCode = Receive-Job $job
    if ($exitCode -ne 0 -or !$probed) { throw 'Integration test did not pass all probes.' }
} finally {
    if ($job.State -eq 'Running') { Stop-Job $job }
    Remove-Job $job
}
