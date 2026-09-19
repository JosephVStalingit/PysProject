# _pull_results.ps1 -- pull the closed-circuit sweep results back from the HPC.
#
# Deliberately pulls ONLY results/circuit.csv (+ .names) and solve.log.
# The results/case_t*.vtu tree is ~3 GB per case -- 20 GB+ for the sweep --
# and contains nothing that is not already in the CSV.
#
# ssh/scp to this cluster intermittently fails with exit 255 ("Connection
# closed by ..."), so every transfer is retried.

param(
    [string]$Host_   = 'cancon.hpccube.com',
    [int]   $Port    = 65023,
    [string]$User    = 'josephvstalin',
    [string]$Key     = "$env:USERPROFILE\.ssh\cancon_key",
    [string]$OutDir  = (Join-Path $PSScriptRoot 'hpc\results'),
    [switch]$WithLog
)

$ErrorActionPreference = 'Continue'
$curves = @(
    'empty',
    'N25_L040_al_closed', 'N25_L040_cu_closed',
    'N50_L040_al_closed', 'N50_L040_cu_closed',
    'N100_L040_al_closed', 'N100_L040_cu_closed'
)

$remote = '/public/home/josephvstalin/pysproject/cases'

function Get-Remote {
    param([string]$Rel, [string]$Dest)
    # Call scp DIRECTLY with an argument ARRAY.  Going through `cmd /c "..."`
    # or concatenating the command with `+` makes PowerShell split it into
    # separate arguments and scp prints its usage instead.
    $src = "${User}@${Host_}:$remote/$Rel"
    $a = @('-q', '-P', "$Port", '-i', $Key,
           '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=30',
           $src, $Dest)
    for ($i = 1; $i -le 4; $i++) {
        & scp @a 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $Dest) -and
            (Get-Item $Dest -ErrorAction SilentlyContinue).Length -gt 0) {
            return $true
        }
        Remove-Item $Dest -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    return $false
}

New-Item -ItemType Directory -Force $OutDir | Out-Null

$ok = 0; $miss = 0
foreach ($c in $curves) {
    $dir = Join-Path $OutDir $c
    New-Item -ItemType Directory -Force $dir | Out-Null

    $csv  = Get-Remote "$c/results/circuit.csv"       (Join-Path $dir 'circuit.csv')
    $null = Get-Remote "$c/results/circuit.csv.names" (Join-Path $dir 'circuit.csv.names')
    if ($WithLog) {
        $null = Get-Remote "$c/solve.log" (Join-Path $dir 'solve.log')
    }

    if ($csv) {
        $rows = (Get-Content (Join-Path $dir 'circuit.csv')).Count
        Write-Host ("  [ok]   {0,-22} {1,5} rows  {2,7:N1} kB" -f `
            $c, $rows, ((Get-Item (Join-Path $dir 'circuit.csv')).Length / 1KB))
        $ok++
    } else {
        Write-Host ("  [miss] {0,-22} (no circuit.csv)" -f $c) -ForegroundColor DarkGray
        $miss++
    }
}

Write-Host ""
Write-Host "  pulled $ok case(s), $miss without a circuit.csv (expected: 'empty')"
Write-Host "  into $OutDir"
