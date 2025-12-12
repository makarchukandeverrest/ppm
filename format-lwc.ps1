# PowerShell script to format LWC HTML files using VS Code's HTML formatter
Write-Host "Formatting LWC HTML files..." -ForegroundColor Green

# Get all LWC HTML files
$lwcFiles = Get-ChildItem -Path "force-app/main/default/lwc" -Recurse -Filter "*.html"

foreach ($file in $lwcFiles) {
    Write-Host "Formatting $($file.FullName)..." -ForegroundColor Yellow

    # Use VS Code's HTML formatter
    code --wait $file.FullName
}

Write-Host "LWC HTML files formatting complete!" -ForegroundColor Green
