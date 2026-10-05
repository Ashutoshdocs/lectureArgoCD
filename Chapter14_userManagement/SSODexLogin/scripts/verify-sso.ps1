# -----------------------------------------------------------------------------
# Runs the SSO permission test matrix from the Windows laptop.
#
# Prerequisite: log in once per user with SSO (a browser window opens each time):
#   argocd login <NODE-IP>:30443 --sso --insecure --grpc-web --name charlie   # log in as charlie
#   argocd login <NODE-IP>:30443 --sso --insecure --grpc-web --name diana     # log in as diana
#   argocd login <NODE-IP>:30443 --sso --insecure --grpc-web --name eve       # log in as eve
# and make sure dev-app exists (README step 14.3).
#
# Usage:  .\scripts\verify-sso.ps1
# -----------------------------------------------------------------------------

function Test-Step {
    param([string]$Title, [string]$Expect, [scriptblock]$Cmd)
    Write-Host ""
    Write-Host "--- $Title" -ForegroundColor Cyan
    Write-Host "    expected: $Expect" -ForegroundColor DarkGray
    & $Cmd 2>&1 | ForEach-Object { Write-Host "    $_" }
}

$expect = @{
    charlie = @{ groups = "dev-team"; list = "dev-app"; get = "details"; sync = "succeeds"; set = "succeeds"; delete = "permission denied" }
    diana   = @{ groups = "ops-team"; list = "dev-app"; get = "details"; sync = "permission denied"; set = "permission denied"; delete = "permission denied" }
    eve     = @{ groups = "(empty)";  list = "nothing"; get = "permission denied"; sync = "permission denied"; set = "permission denied"; delete = "permission denied" }
}

foreach ($user in @("charlie", "diana", "eve")) {
    $e = $expect[$user]
    Write-Host ""
    Write-Host "==================== SSO context: $user ====================" -ForegroundColor Yellow
    argocd context $user | Out-Null

    Test-Step "Identity from Dex"           "groups: $($e.groups)" { argocd account get-user-info }
    Test-Step "argocd app list"             $e.list                { argocd app list }
    Test-Step "argocd app get dev-app"      $e.get                 { argocd app get dev-app }
    Test-Step "argocd app sync dev-app"     $e.sync                { argocd app sync dev-app }
    Test-Step "scale dev-app to 3"          $e.set                 { argocd app set dev-app --kustomize-replica dev-web=3 }
    Test-Step "argocd app delete dev-app"   $e.delete              { argocd app delete dev-app --yes }
    Test-Step "can-i delete?"               "no"                   { argocd account can-i delete applications 'dev-project/dev-app' }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
