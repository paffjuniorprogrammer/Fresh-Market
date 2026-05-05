param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceRoleKey,

    [string]$FirebaseJsonPath = "c:\Users\PAFF-DADDY\Downloads\fresh-market-f1ca6-firebase-adminsdk-fbsvc-ce7a1e2bd5.json",

    [string]$ProjectRef = "qhpfppsdjmibucurucui"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FirebaseJsonPath)) {
    throw "Firebase service account JSON not found at: $FirebaseJsonPath"
}

$firebase = Get-Content -Raw $FirebaseJsonPath | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($firebase.project_id) -or
    [string]::IsNullOrWhiteSpace($firebase.client_email) -or
    [string]::IsNullOrWhiteSpace($firebase.private_key)) {
    throw "Firebase JSON is missing project_id, client_email, or private_key."
}

Write-Host "Using Firebase project: $($firebase.project_id)" -ForegroundColor Green
Write-Host "Using Supabase project ref: $ProjectRef" -ForegroundColor Green

npx supabase login
npx supabase link --project-ref $ProjectRef

npx supabase secrets set `
  FCM_PROJECT_ID=$firebase.project_id `
  FCM_CLIENT_EMAIL=$firebase.client_email `
  FCM_PRIVATE_KEY="$($firebase.private_key)" `
  SUPABASE_SERVICE_ROLE_KEY=$ServiceRoleKey

npx supabase functions deploy notify-admin-new-order --project-ref $ProjectRef

Write-Host "Push notification secrets set and function deployed." -ForegroundColor Green
