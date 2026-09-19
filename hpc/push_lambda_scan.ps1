<#
.SYNOPSIS
    hpc/push_lambda_scan.ps1 -- upload the staged static scan and submit it.

.DESCRIPTION
    Uploads (NO solving happens on this box):
        hpc\lambda_scan\*          ->  ~/pysproject/lambda_scan/     (29 SIFs + manifest)
        hpc\run_lambda_scan.sh     ->  ~/                          (the array job)
        hpc\_submit_lambda_scan.sh ->  ~/                          (the submitter)
        hpc\cases\*\case.sif       ->  ~/pysproject/cases/<case>/  (sensor-load SIFs)

    then verifies the remote mesh matches the local one and submits 29 array
    tasks as a SINGLE array job, split into 3 arrays of <=10 tasks so it stays
    well under `QOSMaxSubmitJobPerUserLimit = 20`.

.EXAMPLE
    powershell -File hpc/push_lambda_scan.ps1
    powershell -File hpc/push_lambda_scan.ps1 -NoSubmit      # upload + verify only
#>
param(
    [switch] $NoSubmit,
    [switch] $NoFixMesh
)

$ErrorActionPreference = "Stop"
$Key = "$env:USERPROFILE\.ssh\cancon_key"
$Host_ = "cancon.hpccube.com"
$Port = 65023
$User = "josephvstalin"
# NOTE: ssh commands may use `~` (a real login shell expands it), but scp on
# Windows-OpenSSH speaks SFTP and does NOT expand `~` -- scp targets must be
# ABSOLUTE.  pull.ps1 uses the same absolute base for the same reason.
$Abs = "/public/home/josephvstalin"
$Root = Split-Path -Parent $PSScriptRoot

function Rsh([string] $cmd, [int] $tries = 3) {
    # Same stderr-vs-ErrorActionPreference trap as ScpTo: relax it around the
    # call so the retry loop actually runs, and judge by the exit code.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        for ($i = 1; $i -le $tries; $i++) {
            $o = & ssh -o BatchMode=yes -o ConnectTimeout=30 -p $Port -i $Key "$User@$Host_" $cmd 2>&1
            if ($LASTEXITCODE -eq 0) { return $o }
            Write-Host "   ssh retry $i (exit $LASTEXITCODE)" -ForegroundColor DarkYellow
            Start-Sleep -Seconds 3
        }
    } finally {
        $ErrorActionPreference = $prev
    }
    throw "ssh failed: $cmd"
}
function ScpTo([string] $local, [string] $remote, [int] $tries = 4) {
    # cmd /c keeps PowerShell from re-parsing the -i and user@host:path args.
    #
    # TWO TRAPS (both cost a debugging round here):
    #   * with $ErrorActionPreference = "Stop" ANY line scp writes to stderr
    #     (even a benign "Warning: Permanently added ... known hosts") becomes a
    #     TERMINATING error, so a retry loop never gets to run and the real
    #     message is buried in PowerShell's NativeCommandError wrapper.  The
    #     preference is therefore relaxed around the call and the exit code is
    #     what decides.
    #   * scp on Windows-OpenSSH speaks SFTP and does NOT expand a remote `~`,
    #     hence the absolute $Abs targets (same as hpc/pull.ps1).
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        for ($i = 1; $i -le $tries; $i++) {
            # -O = legacy scp protocol (the remote login SHELL does the copy).
            # The SFTP subsystem on this cluster intermittently cannot resolve
            # /public/home/... ("dest open ... No such file or directory") while
            # the same path is fine in every shell command, so the shell-based
            # protocol is tried first and plain SFTP is only the fallback.
            $proto = if ($i -eq 1) { "-O " } else { "" }
            $out = (& cmd /c "scp $proto-o BatchMode=yes -o ConnectTimeout=30 -P $Port -i `"$Key`" -r `"$local`" `"$User@${Host_}:$remote`"" 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0) { return }
            Write-Host "   scp retry $i (exit $LASTEXITCODE, proto='$proto'): $local" -ForegroundColor DarkYellow
            if ($out) { Write-Host "      $(($out -split "`n")[0])" -ForegroundColor DarkGray }
            Start-Sleep -Seconds 3
        }
    } finally {
        $ErrorActionPreference = $prev
    }
    throw "scp failed after $tries tries: $local -> $remote"
}

function SendTree([string] $parent, [string] $leaf, [string] $remoteDir, [int] $tries = 3) {
    # tar-over-ssh instead of scp.
    #
    # WHY: scp on this box CANNOT resolve the remote /public/home/... paths --
    # both the SFTP subsystem ("dest open ... No such file or directory",
    # "realpath ... No such file or directory") and the legacy -O protocol fail
    # repeatedly, while every single ssh SHELL command (ls, head, mkdir, sbatch)
    # succeeds.  A tar pipe rides that same reliable shell channel and uploads
    # the whole tree in ONE connection.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        for ($i = 1; $i -le $tries; $i++) {
            $c = "tar -czC `"$parent`" $leaf | ssh -o BatchMode=yes -o ConnectTimeout=30 -p $Port -i `"$Key`" " +
                 "$User@$Host_ `"mkdir -p $remoteDir && cd $remoteDir && tar -xz && echo TAR_OK`""
            $out = (& cmd /c $c 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $out -match 'TAR_OK') { return }
            Write-Host "   tar/ssh retry $i (exit $LASTEXITCODE): $leaf" -ForegroundColor DarkYellow
            if ($out) { Write-Host "      $(($out -split "`n")[0])" -ForegroundColor DarkGray }
            Start-Sleep -Seconds 3
        }
    } finally {
        $ErrorActionPreference = $prev
    }
    throw "tar-over-ssh failed after $tries tries: $parent\$leaf -> $remoteDir"
}

$stage = Join-Path $Root 'hpc\lambda_scan'
$man = Join-Path $stage 'manifest.tsv'
if (-not (Test-Path $man)) { throw "no manifest: run  python hpc\stage_lambda_scan.py  first" }
$n = (Get-Content $man | Where-Object { $_.Trim() -ne '' }).Count
Write-Host "staged points: $n" -ForegroundColor Cyan
if ($n -lt 2) { throw "manifest looks empty" }

Write-Host "== uploading scan SIFs (tar over ssh) ==" -ForegroundColor Cyan
Rsh "rm -rf ~/pysproject/lambda_scan/lambda_scan" | Out-Null   # stray dir from an earlier scp attempt
SendTree (Join-Path $Root 'hpc') 'lambda_scan' "$Abs/pysproject"
$remoteN = (Rsh "ls -d ~/pysproject/lambda_scan/z*/ | wc -l")
$remoteM = (Rsh "wc -l < ~/pysproject/lambda_scan/manifest.tsv")
Write-Host ("   remote scan dirs: {0} (expected {1}), manifest rows: {2}" -f $remoteN, $n, $remoteM) -ForegroundColor DarkGray

Write-Host "== uploading job + submitter scripts ==" -ForegroundColor Cyan
SendTree (Join-Path $Root 'hpc') 'run_lambda_scan.sh' "$Abs"
SendTree (Join-Path $Root 'hpc') '_submit_lambda_scan.sh' "$Abs"

Write-Host "== refreshing case SIFs on the HPC ==" -ForegroundColor Cyan
# stage_lambda_scan.py mirrored the refreshed SIFs into lambda_scan/_cases/<case>/
SendTree (Join-Path $stage '_cases') '.' "$Abs/pysproject/cases"
Write-Host "   (Sensor-load R_load must show up as 0.5012)" -ForegroundColor DarkGray

Write-Host "== verify the remote mesh matches this box ==" -ForegroundColor Cyan
$localMesh = (Get-Content '_static\N100_L040_cu_closed\mesh\mesh.header' -ErrorAction SilentlyContinue | Select-Object -First 1)
$remoteMesh = (Rsh "head -1 ~/pysproject/cases/N100_L040_cu_closed/mesh/mesh.header") -join ''
Write-Host ("   local : {0}" -f ([string]$localMesh).Trim()) -ForegroundColor DarkGray
Write-Host ("   remote: {0}" -f ([string]$remoteMesh).Trim()) -ForegroundColor DarkGray
if (([string]$localMesh).Trim() -ne ([string]$remoteMesh).Trim()) {
    if ($NoFixMesh) {
        throw "MESH DIFFERS: upload ~/pysproject/cases/N100_L040_cu_closed/mesh/ by hand, or drop -NoFixMesh"
    }
    Write-Host "   !! mesh differs -- uploading the local mesh/ (override with -NoFixMesh)" -ForegroundColor Yellow
    SendTree (Join-Path $Root '_static\N100_L040_cu_closed') 'mesh' "$Abs/pysproject/cases/N100_L040_cu_closed"
    $chk = (Rsh "head -1 ~/pysproject/cases/N100_L040_cu_closed/mesh/mesh.header") -join ''
    Write-Host ("   now   : {0}" -f ([string]$chk).Trim()) -ForegroundColor DarkGray
} else {
    Write-Host "   meshes identical -- OK" -ForegroundColor Green
}


if ($NoSubmit) { Write-Host "NoSubmit: stopping before sbatch." -ForegroundColor Yellow; return }

Write-Host "== submitting ==" -ForegroundColor Cyan
Rsh "cd ~ && bash _submit_lambda_scan.sh $n"
Write-Host ""
Rsh "squeue -u `$USER -o '%.10i %.12j %.10P %.8T %.10M %R' | head -20"
