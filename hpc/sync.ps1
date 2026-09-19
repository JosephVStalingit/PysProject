<#
.SYNOPSIS
    hpc/sync.ps1 -- move study cases to / from the HPC.

.DESCRIPTION
    The HPC (cancon.hpccube.com) is the primary execution environment from
    now on; this box only builds meshes (gmsh) and post-processes results.

    Flow:
       1.  python hpc\make_case.py --length ... --level ...   (local, gmsh)
       2.  .\hpc\sync.ps1 -Upload                              (cases + scripts)
       3.  ssh ... "cd ~/pysproject && bash submit_all.sh"      (Slurm)
       4.  .\hpc\sync.ps1 -Download                            (results)
       5.  post-process locally

.EXAMPLE
    .\hpc\sync.ps1 -Upload
    .\hpc\sync.ps1 -Upload -Only L160
    .\hpc\sync.ps1 -Download
    .\hpc\sync.ps1 -Status
#>
param(
    [switch] $Upload,
    [switch] $Download,
    [switch] $Status,
    [string] $Only = "",          # substring filter for case names
    [switch] $IncludeMesh         # also (re)send mesh/ (big; default: send once)
)

$ErrorActionPreference = "Stop"
$Key  = "$env:USERPROFILE\.ssh\cancon_key"
$Host_ = "cancon.hpccube.com"
$Port = 65023
$User = "josephvstalin"
$Remote = "~/pysproject"
$Root = Split-Path -Parent $PSScriptRoot

function Invoke-Rsh([string] $cmd) {
    ssh -o BatchMode=yes -o ConnectTimeout=30 -p $Port -i $Key `
        "$User@$Host_" $cmd
}

if ($Status) {
    Invoke-Rsh "cd $Remote 2>/dev/null && ls cases/ && echo '--- queue ---' && squeue -u `$USER -o '%.10i %.28j %.8T %.10M %R'"
    return
}

if ($Upload) {
    $dirs = Get-ChildItem -Path (Join-Path $Root 'hpc\cases') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'case.sif') } |
            Where-Object { $Only -eq "" -or $_.Name -like "*$Only*" }
    if (-not $dirs) { Write-Host "no cases matched '$Only'" -ForegroundColor Yellow; return }

    Invoke-Rsh "mkdir -p $Remote/cases $Remote/scripts"

    # scripts (small, always refreshed)
    scp -o BatchMode=yes -P $Port -i $Key `
        (Join-Path $Root 'hpc\run_case.slurm') `
        (Join-Path $Root 'hpc\submit_all.sh') `
        "${User}@${Host_}:$Remote/scripts/"

    foreach ($d in $dirs) {
        Write-Host "== uploading $($d.Name)" -ForegroundColor Cyan
        Invoke-Rsh "mkdir -p $Remote/cases/$($d.Name)"
        # case definition + SIF are tiny and must always be current
        scp -o BatchMode=yes -P $Port -i $Key `
            (Join-Path $d.FullName 'config.json') `
            (Join-Path $d.FullName 'case.sif') `
            (Join-Path $d.FullName 'study.json') `
            "${User}@${Host_}:$Remote/cases/$($d.Name)/"

        # Only model3d.msh is uploaded: run_case.slurm runs ElmerGrid on the
        # compute node, which avoids shipping the (larger) converted mesh/.
        if ($IncludeMesh -or -not (Invoke-Rsh "test -f $Remote/cases/$($d.Name)/model3d.msh && echo yes")) {
            $sizeof = "{0:N1} MB" -f ((Get-Item (Join-Path $d.FullName 'model3d.msh')).Length / 1MB)
            Write-Host "   model3d.msh ($sizeof) ..." -ForegroundColor DarkGray
            scp -o BatchMode=yes -P $Port -i $Key `
                (Join-Path $d.FullName 'model3d.msh') `
                "${User}@${Host_}:$Remote/cases/$($d.Name)/"
        } else {
            Write-Host "   model3d.msh already on the HPC (use -IncludeMesh to force)" -ForegroundColor DarkGray
        }
    }
    Write-Host "done. Next: ssh ... 'cd $Remote && bash submit_all.sh'" -ForegroundColor Green
}

if ($Download) {
    $dirs = Get-ChildItem -Path (Join-Path $Root 'hpc\cases') -Directory |
            Where-Object { $Only -eq "" -or $_.Name -like "*$Only*" }
    foreach ($d in $dirs) {
        # two naming conventions coexist:
        #   case_t*.vtu        from run_case.slurm   (monolithic)
        #   case_w*_t*.vtu     from run_window.slurm (windowed)
        #           + solve.log / solve_w*.log
        $n1 = Invoke-Rsh "ls $Remote/cases/$($d.Name)/results/case_t*.vtu 2>/dev/null | wc -l"
        $n2 = Invoke-Rsh "ls $Remote/cases/$($d.Name)/results/case_w*_t*.vtu 2>/dev/null | wc -l"
        $n = [int]$n1 + [int]$n2
        Write-Host "== $($d.Name): $n frames ($n1 mono, $n2 windowed)" -ForegroundColor Cyan
        if ($n -le 0) { continue }
        New-Item -ItemType Directory -Force (Join-Path $d.FullName 'results') | Out-Null
        scp -o BatchMode=yes -P $Port -i $Key `
            "${User}@${Host_}:$Remote/cases/$($d.Name)/results/case_t*.vtu" `
            "${User}@${Host_}:$Remote/cases/$($d.Name)/results/case_w*_t*.vtu" `
            "${User}@${Host_}:$Remote/cases/$($d.Name)/solve.log" `
            "${User}@${Host_}:$Remote/cases/$($d.Name)/solve_w*.log" `
            (Join-Path $d.FullName 'results\')
    }
    Write-Host "done." -ForegroundColor Green
}
