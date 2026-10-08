# ============================================
# Install Argo CD CLI on Windows
# ============================================

$ErrorActionPreference = "Stop"

$Version = "v3.1.8"
$InstallDir = "$env:USERPROFILE\bin"
$ExePath = "$InstallDir\argocd.exe"

Write-Host "============================================"
Write-Host "Installing Argo CD CLI"
Write-Host "============================================"

# Create installation directory
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Download URL
$DownloadUrl = "https://github.com/argoproj/argo-cd/releases/download/$Version/argocd-windows-amd64.exe"

$TempFile = "$env:TEMP\argocd.exe"

Write-Host "Downloading Argo CD CLI $Version..."
Invoke-WebRequest `
    -Uri $DownloadUrl `
    -OutFile $TempFile

# Move executable
Write-Host "Installing argocd.exe..."
Copy-Item $TempFile $ExePath -Force

# Add installation directory to User PATH
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

if (-not ($UserPath -split ";" | Where-Object { $_ -eq $InstallDir })) {

    if ([string]::IsNullOrEmpty($UserPath)) {
        $NewUserPath = $InstallDir
    }
    else {
        $NewUserPath = "$UserPath;$InstallDir"
    }

    [Environment]::SetEnvironmentVariable(
        "Path",
        $NewUserPath,
        "User"
    )

    Write-Host "Added $InstallDir to User PATH"
}
else {
    Write-Host "$InstallDir already exists in User PATH"
}

# Update PATH for current PowerShell session
$env:Path = "$InstallDir;$env:Path"

Write-Host ""
Write-Host "============================================"
Write-Host "Verification"
Write-Host "============================================"

# Check executable
if (Test-Path $ExePath) {
    Write-Host "argocd.exe found at:"
    Write-Host $ExePath
}
else {
    Write-Error "Argo CD CLI installation failed."
}

# Check command
Write-Host ""
Write-Host "Argo CD CLI version:"
argocd version --client

Write-Host ""
Write-Host "============================================"
Write-Host "Installation completed successfully"
Write-Host "============================================"