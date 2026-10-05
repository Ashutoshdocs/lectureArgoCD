# -----------------------------------------------------------------------------
# Runs the permission test matrix from the Windows laptop.
# Prerequisite: you have already logged in once as each user with
#   argocd login <NODE-IP>:30443 --username alice ... --name alice
#   argocd login <NODE-IP>:30443 --username bob   ... --name bob
#
# Usage (PowerShell):
#   .\scripts\verify-permissions.ps1
# -----------------------------------------------------------------------------

function Test-Step {
    param([string]$Title, [string]$Expect, [scriptblock]$Cmd)
    Write-Host ""
    Write-Host "--- $Title" -ForegroundColor Cyan
    Write-Host "    expected: $Expect" -ForegroundColor DarkGray
    & $Cmd 2>&1 | ForEach-Object { Write-Host "    $_" }
}

foreach ($pair in @(@("alice","bob"), @("bob","alice"))) {
    $me    = $pair[0]
    $other = $pair[1]

    Write-Host ""
    Write-Host "==================== Context: $me ====================" -ForegroundColor Yellow
    argocd context $me | Out-Null

    Test-Step "Who am I?"                       "loggedIn: true, username: $me" { argocd account get-user-info }
    Test-Step "List applications"               "only $me-app"                  { argocd app list }
    Test-Step "List projects"                   "only $me-project"              { argocd proj list }
    Test-Step "Get own app"                     "details shown"                 { argocd app get "$me-app" }
    Test-Step "Get $other's app"                "permission denied"             { argocd app get "$other-app" }
    Test-Step "Sync own app"                    "sync succeeds"                 { argocd app sync "$me-app" }
    Test-Step "Can I delete my app?"            "no"                            { argocd account can-i delete applications "$me-project/$me-app" }
    Test-Step "Can I sync my app?"              "yes"                           { argocd account can-i sync applications "$me-project/$me-app" }
    Test-Step "Can I get $other's app?"         "no"                            { argocd account can-i get applications "$other-project/$other-app" }
    Test-Step "Delete own app (should fail)"    "permission denied"             { argocd app delete "$me-app" --yes }
    Test-Step "Delete $other's app (should fail)" "permission denied"           { argocd app delete "$other-app" --yes }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
