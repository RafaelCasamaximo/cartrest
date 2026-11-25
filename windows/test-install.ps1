param(
    [string]$Output = (Join-Path $env:TEMP "cartrest-smoke"),
    [string]$InstallerDirectory = (Join-Path $PSScriptRoot "../dist/windows")
)

$ErrorActionPreference = "Stop"
$installer = @(Get-ChildItem -LiteralPath $InstallerDirectory -Filter "*-Windows-x64-Setup.exe")
if ($installer.Count -ne 1) { throw "Expected exactly one Windows installer." }
$expected = (Get-Content "$($installer[0].FullName).sha256").Split(" ")[0]
$actual = (Get-FileHash $installer[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "The installer hash did not match." }

$root = Join-Path $env:LOCALAPPDATA "Programs\Cartrest"
if (Test-Path (Join-Path $root "Uninstall.exe")) { throw "Use a clean Windows test account." }
$install = Start-Process -FilePath $installer[0].FullName -ArgumentList "/S" -PassThru -Wait
if ($install.ExitCode -ne 0) { throw "The installer exited with $($install.ExitCode)." }
$application = Join-Path $root "Cartrest.exe"
$uninstall = Join-Path $root "Uninstall.exe"
if (!(Test-Path $application) -or !(Test-Path $uninstall)) { throw "The installation is incomplete." }
$registry = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest"
if (!(Test-Path $registry)) { throw "The application was not registered for uninstall." }
$link = Join-Path ([Environment]::GetFolderPath("Programs")) "Cartrest.lnk"
if (!(Test-Path $link)) { throw "The Start menu shortcut is missing." }

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$app = Start-Process -FilePath $application -ArgumentList "--smoke-test", "`"$Output`"" -PassThru
if (!$app.WaitForExit(120000)) {
    $app.Kill()
    throw "The installed app did not complete its native checks within two minutes."
}
if ($app.ExitCode -ne 0 -or !(Test-Path (Join-Path $Output "passed.txt"))) {
    $failure = Join-Path $Output "failure.txt"
    if (Test-Path $failure) { Get-Content $failure }
    throw "The installed app exited with $($app.ExitCode)."
}

# Confirm that the uninstaller removes its own files and leaves another file untouched.
$sample = Join-Path $root "unrelated.txt"
Set-Content -LiteralPath $sample -Value "Keep this file."
$result = Start-Process -FilePath $uninstall -ArgumentList "/S" -PassThru -Wait
if ($result.ExitCode -ne 0 -or (Test-Path $application) -or (Test-Path $link) -or (Test-Path $registry)) {
    throw "The silent uninstall did not remove Cartrest and its registration."
}
if (!(Test-Path $sample)) { throw "The uninstaller removed a file outside its manifest." }
Remove-Item -LiteralPath $sample
Write-Output "Verified setup, native workspaces, exports, and uninstall."
