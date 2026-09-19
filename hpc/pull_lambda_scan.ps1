<#
.SYNOPSIS
    hpc/pull_lambda_scan.ps1 -- fetch the static scan results (circuit.csv) back.

.DESCRIPTION
    The 29 points write ~1 kB of circuit.csv each; nothing else is needed for
    the Lambda_mot(z) analysis.  Pulled as ONE tar stream over ssh (see
    push_lambda_scan.ps1 for why scp is unusable from this box) into
    _static\lambda_scan_results\<tag>\results\circuit.csv.

.EXAMPLE
    powershell -File hpc/pull_lambda_scan.ps1
#>
param(
    [string] $Remote = "/public/home/josephvstalin/hpc_lambda_scan"
)

$ErrorActionPreference = "Continue"
$Key = "$env:USERPROFILE\.ssh\cancon_key"
$Host_ = "cancon.hpccube.com"
$Port = 65023
$User = "josephvstalin"
$Root = Split-Path -Parent $PSScriptRoot
$Local = Join-Path $Root '_static\lambda_scan_results'
New-Item -ItemType Directory -Force $Local | Out-Null

Write-Host "== remote state ==" -ForegroundColor Cyan
& ssh -o BatchMode=yes -o ConnectTimeout=30 -p $Port -i $Key "$User@$Host_" `
    "echo done_dirs=\$(ls -d $Remote/z*/ 2>/dev/null | wc -l); echo csvs=\$(ls $Remote/z*/results/circuit.csv 2>/dev/null | wc -l); squeue -u `$USER -o '%.10i %.10j %.8T %.10M' | head -6"

Write-Host "== pulling circuit.csv files (tar over ssh) ==" -ForegroundColor Cyan
# `ls ... | tar -T -` avoids both an unexpanded glob and the "empty list makes
# tar read stdin" trap.  GNU tar on the cluster supports -T.
$c = "ssh -o BatchMode=yes -o ConnectTimeout=30 -p $Port -i `"$Key`" $User@$Host_ " +
     "`"cd $Remote && ls -d z*/results/circuit.csv 2>/dev/null | tar -czf - -T -`" | tar -xzf - -C `"$Local`""
& cmd /c $c 2>&1 | Select-Object -Last 3

$n = (Get-ChildItem $Local -Recurse -Filter 'circuit.csv' -ErrorAction SilentlyContinue).Count
Write-Host ""
Write-Host ("local circuit.csv files: {0}" -f $n) -ForegroundColor Green
Write-Host ("  in {0}" -f $Local) -ForegroundColor DarkGray
