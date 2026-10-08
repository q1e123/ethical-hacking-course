<#
.SYNOPSIS
    setup.ps1 - AI Security Workshop environment installer for Windows.

.DESCRIPTION
    Installs uv, builds the shared virtual environment, pulls every dependency
    (CPU-only PyTorch), scaffolds .env, then verifies the whole thing.
    The Windows counterpart of setup.sh; same steps, same flags.

      .\setup.ps1                 install everything, then verify
      .\setup.ps1 -Verify         verify an existing install, change nothing
      .\setup.ps1 -Help           all options

    If script execution is blocked, run it once with:
      powershell -ExecutionPolicy Bypass -File .\setup.ps1

    Works on Windows PowerShell 5.1 and PowerShell 7+.
#>
param(
    [Alias('V')] [switch] $Verify,
    [Alias('S')] [switch] $SkipVerify,
    [Alias('r')] [switch] $Recreate,
    [Alias('p')] [string] $Python = $(if ($env:WORKSHOP_PYTHON) { $env:WORKSHOP_PYTHON } else { '3.12' }),
    [switch] $ShowOutput,
    [switch] $NoColor,
    [Alias('h')] [switch] $Help,
    [switch] $Version
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------- constants ----
$SCRIPT_VERSION = '1.0.0'
$ROOT        = $PSScriptRoot
$VENV_DIR    = Join-Path $ROOT '.venv'
$VENV_PY     = Join-Path $VENV_DIR 'Scripts\python.exe'
$TORCH_INDEX = 'https://download.pytorch.org/whl/cpu'
$UV_INSTALLER = 'https://astral.sh/uv/install.ps1'

# ----------------------------------------------------------------- state ----
$script:LogFile    = ''
$script:Step       = 0
$script:TotalSteps = 6
$script:Summary    = New-Object System.Collections.Generic.List[object]
$script:Warnings   = 0
$script:UseColor   = -not ($NoColor -or $env:NO_COLOR)

# ------------------------------------------------------ style and glyphs ----
# The source stays pure ASCII so Windows PowerShell 5.1 parses it whatever the
# file encoding; Unicode glyphs are built from code points, and only used where
# the console can actually draw them.
$fancy = ($PSVersionTable.PSVersion.Major -ge 7) -or [bool]$env:WT_SESSION
if ($fancy) {
    $G = @{ Ok = [char]0x2714; Fail = [char]0x2716; Warn = [char]0x25B2; Step = [char]0x25B8
            Info = [char]0x00B7; Sep = [char]0x00B7; Hz = [char]0x2500; Vt = [char]0x2502
            TL = [char]0x256D; TR = [char]0x256E; BL = [char]0x2570; BR = [char]0x256F }
} else {
    $G = @{ Ok = '+'; Fail = 'x'; Warn = '!'; Step = '>'; Info = '-'; Sep = '-'
            Hz = '-'; Vt = '|'; TL = '+'; TR = '+'; BL = '+'; BR = '+' }
}

# ------------------------------------------------------------- printing ----
# out <text> [colour] [-NoNewline] - Write-Host colours work on every console,
# including the legacy conhost that ignores ANSI escapes.
function out([string] $Text, [string] $Color = '', [switch] $NoNewline) {
    if ($script:UseColor -and $Color) {
        Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewline
    } else {
        Write-Host $Text -NoNewline:$NoNewline
    }
}

function rule([int] $n = 66) { ([string]$G.Hz) * $n }

function box([string] $Color, [string[]] $Rows, [int] $Pad = 62) {
    out ''
    out ("  " + $G.TL + (rule $Pad) + $G.TR) $Color
    foreach ($r in $Rows) {
        out ("  " + $G.Vt + "  ") $Color -NoNewline
        out ($r.PadRight($Pad - 4)) -NoNewline
        out ("  " + $G.Vt) $Color
    }
    out ("  " + $G.BL + (rule $Pad) + $G.BR) $Color
}

function banner {
    box 'Blue' @(
        "AI Security Workshop  $($G.Sep)  environment setup (windows)",
        "uv $($G.Sep) python $Python $($G.Sep) cpu-only torch"
    )
}

function step([string] $Label) {
    $script:Step++
    out ''
    out ("  " + $G.Step + " ") 'Blue' -NoNewline
    out $Label 'White' -NoNewline
    out " ($script:Step/$script:TotalSteps)" 'DarkGray'
}

function mark([string] $Glyph, [string] $Color, [string] $Label, [string] $Detail) {
    out ("     " + $Glyph + " ") $Color -NoNewline
    if ($Detail) { out $Label -NoNewline; out ("  " + $Detail) 'DarkGray' } else { out $Label }
}
function ok([string] $Label, [string] $Detail = '')   { mark $G.Ok 'Green' $Label $Detail }
function warn([string] $Label, [string] $Detail = '') { mark $G.Warn 'Yellow' $Label $Detail; $script:Warnings++ }
function bad([string] $Label, [string] $Detail = '')  { mark $G.Fail 'Red' $Label $Detail }
function info([string] $Text) { out ("     " + $G.Info + " " + $Text) 'DarkGray' }

function log_hint {
    if (-not $script:LogFile -or -not (Test-Path -LiteralPath $script:LogFile)) { return }
    out ''
    out "  last lines of $script:LogFile" 'DarkGray'
    out ("  " + (rule)) 'DarkGray'
    Get-Content -LiteralPath $script:LogFile -Tail 15 | ForEach-Object { out "  $_" 'DarkGray' }
    out ("  " + (rule)) 'DarkGray'
}

# A terminating error the main loop catches and reports once.
function die([string] $Message, [string] $Hint = '') {
    $e = New-Object System.Exception $Message
    $e.Data['setup.abort'] = $true
    $e.Data['setup.hint'] = $Hint
    throw $e
}

function record([string] $Name, [string] $Value) { $script:Summary.Add(@($Name, $Value)) }

function have([string] $Name) { [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue) }

# task <label> <exe> <args...> - run a native command, keep its output in the
# log, return $true on exit code 0. EAP is relaxed for the call so stderr lines
# from the tool (uv prints progress there) never turn into terminating errors.
function task([string] $Label, [string] $Exe, [string[]] $ArgList = @()) {
    Add-Content -LiteralPath $script:LogFile -Value "`n### $Label`n> $Exe $($ArgList -join ' ')"
    if ($ShowOutput) {
        info $Label
        out "     > $Exe $($ArgList -join ' ')" 'DarkGray'
    } else {
        info "$Label ..."
    }

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @ArgList 2>&1 | ForEach-Object {
            $line = "$_"
            Add-Content -LiteralPath $script:LogFile -Value $line
            if ($ShowOutput) { out "       $line" 'DarkGray' }
        }
        $rc = $LASTEXITCODE
    } catch {
        Add-Content -LiteralPath $script:LogFile -Value "$_"
        $rc = 1
    } finally {
        $ErrorActionPreference = $prev
    }
    return ($rc -eq 0)
}

# capture <exe> <args...> - first line of stdout, or $null on failure
function capture([string] $Exe, [string[]] $ArgList = @()) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $o = & $Exe @ArgList 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return (@($o) | Select-Object -First 1)
    } catch { return $null } finally { $ErrorActionPreference = $prev }
}

# succeeds <exe> <args...> - $true when the command exits 0, output discarded
function succeeds([string] $Exe, [string[]] $ArgList = @()) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Exe @ArgList *> $null; return ($LASTEXITCODE -eq 0) }
    catch { return $false } finally { $ErrorActionPreference = $prev }
}

function usage {
    out ''
    out '  setup.ps1' 'White' -NoNewline; out " v$SCRIPT_VERSION" 'DarkGray' -NoNewline
    out ' - install and verify the workshop environment'
    out ''
    out '  USAGE' 'White'
    out '     .\setup.ps1 [options]'
    out '     powershell -ExecutionPolicy Bypass -File .\setup.ps1 [options]' 'DarkGray'
    out ''
    out '  OPTIONS' 'White'
    $opts = @(
        @('-Verify, -V',      'verify only; install nothing, change nothing'),
        @('-SkipVerify, -S',  'install, then stop before verification'),
        @('-Recreate, -r',    'delete and rebuild .venv from scratch'),
        @('-Python VER, -p',  "python for the venv (default: $Python)"),
        @('-ShowOutput',      'stream command output to the console'),
        @('-NoColor',         'disable colour'),
        @('-Help, -h',        'this text'),
        @('-Version',         'print the version')
    )
    foreach ($o in $opts) { out ("     " + $o[0].PadRight(20)) 'Cyan' -NoNewline; out $o[1] }
    out ''
    out '  ENVIRONMENT' 'White'
    out '     WORKSHOP_PYTHON     ' 'Cyan' -NoNewline; out 'same as -Python'
    out '     NO_COLOR            ' 'Cyan' -NoNewline; out 'disable colour'
    out ''
    out '  WHAT IT DOES' 'White'
    out '     1. preflight  - powershell, git, disk space, long paths'
    out '     2. uv         - install via astral.sh if missing'
    out "     3. venv       - .venv on python $Python"
    out '     4. deps       - uv sync against the CPU-only torch index'
    out '     5. config     - .env.example, .env, .gitignore entries'
    out '     6. verify     - uv, venv, lockfile, then verify-environment.py'
    out ''
}

# ================================================================= steps ====

function step_preflight {
    step 'Preflight'

    ok 'powershell' "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

    $onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
    if ($onWindows) { ok 'platform' 'windows' }
    else { warn 'platform' 'not windows - use ./setup.sh here; continuing anyway' }

    if (have 'git') { ok 'git' ((Get-Command git).Source) }
    else { die 'missing required tool: git' 'install it from https://git-scm.com/download/win, then re-run' }

    if (Test-Path -LiteralPath (Join-Path $ROOT 'pyproject.toml')) { ok 'project root' $ROOT }
    else { die 'pyproject.toml not found' "expected it in $ROOT - run setup.ps1 from the repo" }

    try {
        $drive = Get-PSDrive -Name ((Get-Item -LiteralPath $ROOT).PSDrive.Name)
        $freeGiB = [math]::Floor($drive.Free / 1GB)
        if ($drive.Free -gt 4GB) { ok 'disk space' "$freeGiB GiB free" }
        else { warn 'disk space' "$freeGiB GiB free - torch and friends want ~4 GiB" }
    } catch {
        warn 'disk space' 'could not determine free space'
    }

    # torch and transformers ship deeply nested files; past 260 chars Windows
    # refuses them unless long paths are switched on
    if ($onWindows) {
        $lp = $null
        try {
            $lp = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
                    -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled
        } catch { }
        if ($lp -eq 1) { ok 'long paths' 'enabled' }
        elseif ($ROOT.Length -gt 60) {
            warn 'long paths' "disabled and the repo path is $($ROOT.Length) chars - installs may fail"
            info 'fix (admin PowerShell): Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem LongPathsEnabled 1'
            info 'or clone the repo somewhere shorter, e.g. C:\workshop'
        } else { ok 'long paths' 'disabled, but the repo path is short enough' }
    }

    info "log: $script:LogFile"
}

function step_uv {
    step 'Package manager (uv)'

    if (have 'uv') {
        ok 'uv' (capture 'uv' @('--version'))
        record 'uv' 'already installed'
        return
    }

    info 'uv not found - installing from astral.sh'
    # a child shell, so the installer runs under Bypass whatever this host's policy
    $shell = (Get-Process -Id $PID).Path
    $installed = task 'downloading uv installer' $shell @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "irm $UV_INSTALLER | iex")
    if (-not $installed) { die 'uv installation failed' "see $script:LogFile" }

    # the installer drops uv in one of these; make it usable right now
    $candidates = @($env:XDG_BIN_HOME,
                    $(if ($env:CARGO_HOME) { Join-Path $env:CARGO_HOME 'bin' } else { Join-Path $HOME '.cargo\bin' }),
                    (Join-Path $HOME '.local\bin'))
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'uv.exe'))) {
            $env:Path = "$c;$env:Path"
            break
        }
    }

    if (-not (have 'uv')) {
        die 'uv installed but not on PATH' 'open a new terminal so the updated PATH loads, then re-run'
    }

    ok 'uv' (capture 'uv' @('--version'))
    warn 'PATH' 'uv was added to PATH for this session; new terminals pick it up automatically'
    record 'uv' 'installed'
}

function step_venv {
    step 'Virtual environment'

    if ((Test-Path -LiteralPath $VENV_DIR) -and $Recreate) {
        info 'removing old .venv ...'
        try { Remove-Item -LiteralPath $VENV_DIR -Recurse -Force }
        catch { die 'could not remove .venv' 'close any shell or editor that has it activated, then re-run' }
        ok 'old .venv' 'removed'
    }

    if (Test-Path -LiteralPath $VENV_PY) {
        ok '.venv' (capture $VENV_PY @('-V'))
        record 'venv' 'reused'
        return
    }

    if (-not (task "creating .venv on python $Python" 'uv' @('venv', $VENV_DIR, '--python', $Python))) {
        die "could not create a venv on python $Python" 'try another version:  .\setup.ps1 -Python 3.11'
    }

    ok '.venv' (capture $VENV_PY @('-V'))
    record 'venv' "created (python $Python)"
}

function step_deps {
    step 'Dependencies'
    if (-not (succeeds $VENV_PY @('-c', 'import torch'))) {
        info 'first run pulls ~2 GiB of wheels - torch, transformers, scikit-learn'
    }

    $savedVenv = $env:VIRTUAL_ENV
    $env:VIRTUAL_ENV = $VENV_DIR
    try {
        $synced = task 'syncing from uv.lock (cpu-only torch)' 'uv' @('sync', '--extra-index-url', $TORCH_INDEX)
    } finally {
        $env:VIRTUAL_ENV = $savedVenv
    }
    if (-not $synced) {
        die 'dependency sync failed' "re-run with -ShowOutput to watch it, or read $script:LogFile"
    }

    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $count = @(& uv pip list --python $VENV_PY 2>$null | Select-Object -Skip 2).Count
    $ErrorActionPreference = $prev
    ok 'packages installed' "$count"
    record 'deps' "$count packages"
}

function step_config {
    step 'Configuration'

    $example = Join-Path $ROOT '.env.example'
    $envfile = Join-Path $ROOT '.env'
    $hz = [string]$G.Hz

    # same text as setup.sh writes; the rules are drawn with the active glyph
    $template = @(
        "# $hz$hz Groq " + ($hz * 70),
        '# https://console.groq.com/keys',
        'GROQ_API_KEY=your_groq_api_key_here',
        '',
        "# $hz$hz Supabase " + ($hz * 66),
        '# Dashboard -> your project -> Settings -> API',
        '# Only needed for llm/rag-data-leak and agents/rag-injection',
        'SUPABASE_URL=https://your-project.supabase.co',
        'SUPABASE_KEY=your_supabase_anon_key_here'
    ) -join "`n"
    # UTF-8 without BOM and LF endings, so python-dotenv and git see the same file setup.sh writes
    [System.IO.File]::WriteAllText($example, $template + "`n", (New-Object System.Text.UTF8Encoding($false)))
    ok '.env.example' 'written'

    if (Test-Path -LiteralPath $envfile) {
        ok '.env' 'already exists - left untouched'
    } else {
        Copy-Item -LiteralPath $example -Destination $envfile
        # the Windows take on chmod 600: drop inherited ACEs, grant only this user
        # (by SID, so Microsoft and Entra accounts resolve too)
        $locked = $false
        try {
            $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            $locked = succeeds 'icacls' @($envfile, '/inheritance:r', '/grant:r', "*${sid}:F")
        } catch { }
        if (-not $locked) { info '.env could not be restricted to your user - it holds API keys, keep it private' }
        warn '.env' 'created from template - fill in your keys'
        record '.env' 'created, keys pending'
    }

    # a .env full of real keys must never be committable
    $gitignore = Join-Path $ROOT '.gitignore'
    $lines = @()
    if (Test-Path -LiteralPath $gitignore) { $lines = @(Get-Content -LiteralPath $gitignore) }
    $added = @()
    foreach ($pattern in @('.env', '.venv/', '__pycache__/', '*.pyc')) {
        if ($lines -notcontains $pattern) { $added += $pattern }
    }
    if ($added.Count) {
        $raw = ''
        if (Test-Path -LiteralPath $gitignore) { $raw = [System.IO.File]::ReadAllText($gitignore) }
        $prefix = if ($raw.Length -and -not $raw.EndsWith("`n")) { "`n" } else { '' }
        [System.IO.File]::AppendAllText($gitignore, $prefix + (($added -join "`n") + "`n"),
                                        (New-Object System.Text.UTF8Encoding($false)))
        ok '.gitignore' "added $($added -join ' ')"
    } else {
        ok '.gitignore' 'already covers .env and .venv'
    }
}

function step_verify {
    step 'Verification'

    if (have 'uv') { ok 'uv on PATH' (capture 'uv' @('--version')) }
    else { bad 'uv on PATH' 'not found'; return $false }

    if (Test-Path -LiteralPath $VENV_PY) { ok 'venv interpreter' (capture $VENV_PY @('-V')) }
    else { bad 'venv interpreter' "missing - expected $VENV_PY"; return $false }

    $pyMinor = capture $VENV_PY @('-c', 'import sys; print("%d.%d" % sys.version_info[:2])')
    if (succeeds $VENV_PY @('-c', 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)')) {
        ok 'python 3.11+' $pyMinor
    } else { bad 'python 3.11+' "found $pyMinor"; return $false }

    if (task 'checking dependency tree' 'uv' @('pip', 'check', '--python', $VENV_PY)) {
        ok 'dependency tree' 'consistent'
    } else {
        warn 'dependency tree' 'uv pip check reported conflicts - see the log'
    }

    $torchVer = capture $VENV_PY @('-c', 'import torch; print(torch.__version__)')
    if ($torchVer) {
        ok 'torch imports' $torchVer
        if ($torchVer -notlike '*+cpu*') { warn 'torch build' "$torchVer is not the +cpu wheel" }
    } else {
        bad 'torch imports' 'failed - run .\.venv\Scripts\python.exe -c "import torch" to see why'
        return $false
    }

    # by far the most common stumble: running the system python, which sees none
    # of these packages - sklearn, torch and friends live only inside .venv
    if ($env:VIRTUAL_ENV -and ((Resolve-Path -LiteralPath $env:VIRTUAL_ENV -ErrorAction SilentlyContinue).Path -eq $VENV_DIR)) {
        ok 'venv active in shell' $env:VIRTUAL_ENV
    } else {
        warn 'venv active in shell' 'no - a bare `python` will not find these packages'
        info 'activate it:  .\.venv\Scripts\Activate.ps1'
        info 'or skip that: uv run python verify-environment.py'
    }

    $envfile = Join-Path $ROOT '.env'
    if (Test-Path -LiteralPath $envfile) { ok '.env present' }
    else { bad '.env present' 'missing'; return $false }

    $keysPending = [bool](Select-String -LiteralPath $envfile -Pattern '^GROQ_API_KEY=(your_|\s*$)' -Quiet)
    if ($keysPending) { warn 'api keys' 'GROQ_API_KEY is still the placeholder' }
    else { ok 'api keys' 'GROQ_API_KEY looks filled in' }

    # hand off to the project's own deep check (packages + live Groq call).
    # Piped output is not a console, so force UTF-8 or rich's glyphs crash on cp1252.
    out ''
    out '     running verify-environment.py' 'DarkGray'
    out ''
    $saved = @{ PYTHONUTF8 = $env:PYTHONUTF8; PYTHONIOENCODING = $env:PYTHONIOENCODING }
    $env:PYTHONUTF8 = '1'; $env:PYTHONIOENCODING = 'utf-8'
    $prevEnc = $null
    try { $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $ROOT
    try {
        & $VENV_PY verify-environment.py 2>&1 | ForEach-Object {
            $line = "$_"
            Add-Content -LiteralPath $script:LogFile -Value $line
            Write-Host "     $line"
        }
        $rc = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $prev
        if ($prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch { } }
        $env:PYTHONUTF8 = $saved.PYTHONUTF8; $env:PYTHONIOENCODING = $saved.PYTHONIOENCODING
    }

    if ($rc -eq 0) {
        record 'verify' 'all checks passed'
        return $true
    } elseif ($keysPending) {
        record 'verify' 'packages ok, api keys pending'
        warn 'verify-environment.py' 'failed on API keys only - expected until .env is filled in'
        return $true
    } else {
        record 'verify' 'failed'
        return $false
    }
}

# =============================================================== summary ====

function finish([bool] $Failed, [int] $Elapsed) {
    if ($script:Summary.Count) {
        box 'DarkGray' @($script:Summary | ForEach-Object { $_[0].PadRight(14) + $_[1] })
    }

    if ($Failed) {
        out ''
        out ("  " + $G.Fail + " setup incomplete") 'Red' -NoNewline
        out " in ${Elapsed}s $($G.Sep) log: $script:LogFile" 'DarkGray'
        out ''
        return $false
    }

    out ''
    out ("  " + $G.Ok + " environment ready") 'Green' -NoNewline
    $tail = " in ${Elapsed}s"
    if ($script:Warnings) { $tail += " $($G.Sep) $script:Warnings warning(s)" }
    out $tail 'DarkGray'

    out ''
    out '  next' 'White'
    $next = @(
        @('1', 'activate   ', '.\.venv\Scripts\Activate.ps1'),
        @('2', 'add keys   ', 'notepad .env'),
        @('3', 're-verify  ', '.\setup.ps1 -Verify')
    )
    foreach ($n in $next) { out "     $($n[0]) " 'Cyan' -NoNewline; out $n[1] -NoNewline; out $n[2] 'DarkGray' }
    out "     $($G.Info) no activate? " 'DarkGray' -NoNewline; out 'prefix commands with: uv run' 'DarkGray'
    out '     4 ' 'Cyan' -NoNewline; out 'attack     ' -NoNewline; out 'see the README in ml-models\, llm\, agents\' 'DarkGray'
    out ''
    return $true
}

function main {
    $logDir = Join-Path ([System.IO.Path]::GetTempPath()) 'workshop-setup'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:LogFile = Join-Path $logDir ("setup-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
    Set-Content -LiteralPath $script:LogFile -Value "setup.ps1 $SCRIPT_VERSION - $(Get-Date)"

    banner
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $failed = $false

    try {
        if ($Verify) {
            $script:TotalSteps = 2
            step_preflight
            if (-not (step_verify)) { $failed = $true }
        } else {
            if ($SkipVerify) { $script:TotalSteps = 5 }
            step_preflight
            step_uv
            step_venv
            step_deps
            step_config
            if ($SkipVerify) {
                info 'verification skipped (-SkipVerify)'
                record 'verify' 'skipped'
            } elseif (-not (step_verify)) {
                $failed = $true
            }
        }
    } catch {
        if ($_.Exception.Data['setup.abort']) {
            out ''
            out ("  " + $G.Fail + " " + $_.Exception.Message) 'Red'
            $hint = $_.Exception.Data['setup.hint']
            if ($hint) { out ("     " + $hint) 'DarkGray' }
            log_hint
            return 1
        }
        out ''
        out ("  " + $G.Fail + " unexpected failure") 'Red' -NoNewline
        out " ($($_.Exception.Message), line $($_.InvocationInfo.ScriptLineNumber))" 'DarkGray'
        log_hint
        return 1
    }

    if (finish $failed ([int]$clock.Elapsed.TotalSeconds)) { return 0 } else { return 1 }
}

if ($Help)    { usage; exit 0 }
if ($Version) { Write-Output $SCRIPT_VERSION; exit 0 }
exit (main)
