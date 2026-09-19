<#
.SYNOPSIS
    hpc/pull.ps1 -- download VTU frames from the HPC study cases.

.DESCRIPTION
    Downloads results for every case under hpc\cases\ (or a subset).

    WHY NOT plain `scp -r` or a remote glob:
      * the two Slurm scripts write DIFFERENT file names
            run_case.slurm   -> results/case_t0001.vtu
            run_window.slurm -> results/case_w0_t0001.vtu
        so a single glob misses half of them;
      * PowerShell mangles `user@host:path` containing `$` or `*`, and
        OpenSSH-on-Windows then mis-parses the remote spec.
      This script therefore lists the files over ssh and copies them ONE
      BY ONE with the same explicit arguments, which is the only form
      that proved reliable on this box.

.EXAMPLE
    .\hpc\pull.ps1                    # all cases
    .\hpc\pull.ps1 -Only L020         # only cases matching a token
    .\hpc\pull.ps1 -Logs              # also fetch solve logs
#>
param(
    [string] $Only = "",
    [switch] $Logs
)

$KEY  = "$env:USERPROFILE\.ssh\cancon_key"
$HST  = "cancon.hpccube.com"
$PORT = 65023
$USR  = "josephvstalin"
$BASE = "/public/home/josephvstalin/pysproject/cases"
$Root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $KEY)) { throw "private key not found: $KEY" }

$cases = Get-ChildItem (Join-Path $Root 'hpc\cases') -Directory |
         Where-Object { $Only -eq "" -or $_.Name -like "*$Only*" }

$total = 0
foreach ($c in $cases) {
    $d = $c.Name
    $local = Join-Path $c.FullName 'results'
    New-Item -ItemType Directory -Force $local | Out-Null

    $listing = & ssh -o BatchMode=yes -o ConnectTimeout=30 -p $PORT -i $KEY `
                     "$USR@$HST" "ls $BASE/$d/results/*.vtu 2>/dev/null"
    $files = @()
    foreach ($line in $listing) {
        $leaf = Split-Path $line.Trim() -Leaf
        if ($leaf) { $files += $leaf }
    }
    if ($files.Count -eq 0) {
        Write-Host ("{0,-22}   0 frames" -f $d) -ForegroundColor DarkGray
        continue
    }

    $ok = 0
    foreach ($f in $files) {
        $target = Join-Path $local $f
        if (Test-Path $target) { $ok++; continue }     # already have it
        # cmd /c keeps PowerShell from re-parsing the arguments
        & cmd /c "scp -o BatchMode=yes -o ConnectTimeout=30 -P $PORT -i `"$KEY`" `"$USR@${HST}:$BASE/$d/results/$f`" `"$target`"" 2>$null | Out-Null
        if (Test-Path $target) { $ok++ }
    }
    $total += $ok
    Write-Host ("{0,-22} {1,3}/{2,-3} frames" -f $d, $ok, $files.Count) `
        -ForegroundColor Cyan
}

if ($Logs) {
    Write-Host ""
    Write-Host "fetching solve logs..." -ForegroundColor DarkGray
    foreach ($c in $cases) {
        foreach ($pat in @('solve.log', 'solve_w*.log')) {
            & cmd /c "scp -o BatchMode=yes -P $PORT -i `"$KEY`" `"$USR@${HST}:$BASE/$($c.Name)/$pat`" `"$($c.FullName)\`"" 2>$null | Out-Null
        }
    }
}

Write-Host ""
Write-Host "total frames now local: $total" -ForegroundColor Green
