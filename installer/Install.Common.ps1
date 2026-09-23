$script:NexusSource = Split-Path -Parent $PSScriptRoot
function Get-NexusNode {
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    $version = & $node -p 'parseInt(process.versions.node)'
    if ($LASTEXITCODE -ne 0 -or [int]$version -lt 22) { throw 'Instalar Node.js 22 ou superior antes de continuar.' }
    if (-not (Test-Path -LiteralPath (Join-Path $script:NexusSource 'node_modules\pg\package.json'))) {
        Push-Location -LiteralPath $script:NexusSource
        try { $null = & npm.cmd ci --omit=dev --ignore-scripts --no-audit --no-fund 2>&1; if ($LASTEXITCODE -ne 0) { throw 'Dependencias indisponiveis. Executar npm ci na pasta de origem e tentar novamente.' } }
        finally { Pop-Location }
    }
    return $node
}
function Read-NexusProtectedConfig([string]$Path) {
    try {
        $secure = (Get-Content -LiteralPath $Path -Raw).Trim() | ConvertTo-SecureString -ErrorAction Stop
        $credential = New-Object System.Management.Automation.PSCredential('config', $secure)
        $settings = $credential.GetNetworkCredential().Password | ConvertFrom-Json
        if ($settings.product -ne 'NEXUS-CUP' -or $settings.key.Length -lt 32) { throw 'Invalid' }
        return $settings
    } catch { throw 'Configuracao DPAPI invalida ou de outro utilizador/computador Windows. Use um config.dpapi valido desta instalacao.' }
    finally { $secure = $null; $credential = $null }
}
function Save-NexusProtectedConfig([string]$Path, $Settings, [switch]$Overwrite) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    if ((Test-Path -LiteralPath $Path) -and -not $Overwrite) { throw 'Configuracao existente: nao sera substituida.' }
    $plain = $Settings | ConvertTo-Json -Depth 12 -Compress
    $temp = $Path + '.new'
    try {
        $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
        $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $temp -Encoding ASCII
        Move-Item -LiteralPath $temp -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        $plain = $null; $secure = $null
    }
}

function Test-NexusTcpPort([string]$HostName, [int]$Port, [int]$TimeoutMs = 900) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch { return $false }
    finally { $client.Dispose() }
}
function Test-NexusLocalHost([string]$HostName) {
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $h = $HostName.Trim().ToLowerInvariant()
    return $h -in @('localhost','127.0.0.1','::1','.')
}
function Wait-NexusTcpPort([string]$HostName, [int]$Port, [int]$Seconds = 12) {
    $until = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        if (Test-NexusTcpPort $HostName $Port 700) { return $true }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $until)
    return $false
}
function Start-NexusPostgreSQLService([int]$Port) {
    $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)postgres' -or $_.DisplayName -match '(?i)postgres'
    })
    foreach ($service in $services) {
        if ($service.Status -eq 'Running') {
            if (Wait-NexusTcpPort '127.0.0.1' $Port 3) { return $true }
            continue
        }
        try {
            Start-Service -Name $service.Name -ErrorAction Stop
        } catch {
            try {
                $command = "Start-Service -Name '" + ($service.Name -replace "'","''") + "' -ErrorAction Stop"
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
                $elevated = Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -Wait -PassThru
                if ($elevated.ExitCode -ne 0) { continue }
            } catch { continue }
        }
        if (Wait-NexusTcpPort '127.0.0.1' $Port 12) { return $true }
    }
    return $false
}
function Get-NexusPostgresDataCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]
    $swCyber = Split-Path -Parent $script:NexusSource
    foreach ($path in @(
        (Join-Path $swCyber 'Postgres\data'),
        (Join-Path $swCyber 'Postgres\pgdata'),
        (Join-Path $swCyber 'Postgres\data18'),
        (Join-Path $swCyber 'Postgres\18\data')
    )) { if ($path) { $candidates.Add($path) } }

    try {
        $svc = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '(?i)postgres' -or $_.DisplayName -match '(?i)postgres'
        }
        foreach ($item in $svc) {
            if ($item.PathName -match '(?i)-D\s+["'']?([^"'']+?)["'']?(?:\s|$)') {
                $candidates.Add($matches[1].Trim())
            }
        }
    } catch {}

    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $pgRoot = Join-Path $base 'PostgreSQL'
        if (Test-Path -LiteralPath $pgRoot) {
            Get-ChildItem -LiteralPath $pgRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates.Add((Join-Path $_.FullName 'data'))
            }
        }
    }
    return @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'postgresql.conf')) } | Select-Object -Unique)
}
function Get-NexusPgCtlCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $cmd = Get-Command pg_ctl.exe -ErrorAction Stop
        if ($cmd.Source) { $candidates.Add($cmd.Source) }
    } catch {}
    $swCyber = Split-Path -Parent $script:NexusSource
    $portable = Join-Path $swCyber 'Postgres\bin\pg_ctl.exe'
    if (Test-Path -LiteralPath $portable) { $candidates.Add($portable) }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $pgRoot = Join-Path $base 'PostgreSQL'
        if (Test-Path -LiteralPath $pgRoot) {
            Get-ChildItem -LiteralPath $pgRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
                $candidate = Join-Path $_.FullName 'bin\pg_ctl.exe'
                if (Test-Path -LiteralPath $candidate) { $candidates.Add($candidate) }
            }
        }
    }
    return @($candidates | Select-Object -Unique)
}
function Start-NexusPostgreSQLPortable([int]$Port) {
    $pgCtls = @(Get-NexusPgCtlCandidates)
    $dataDirs = @(Get-NexusPostgresDataCandidates)
    if (-not $pgCtls.Count -or -not $dataDirs.Count) { return $false }
    $log = Join-Path $env:TEMP 'NEXUSCUP-postgresql-start.log'
    foreach ($ctl in $pgCtls) {
        foreach ($data in $dataDirs) {
            try {
                $null = & $ctl -D $data -o ("-p {0} -c listen_addresses=127.0.0.1" -f $Port) -l $log start 2>$null
                if (Wait-NexusTcpPort '127.0.0.1' $Port 12) { return $true }
            } catch {}
        }
    }
    return $false
}
function Ensure-NexusPostgreSQL([hashtable]$Options, [string]$Action) {
    if (-not (Test-NexusLocalHost ([string]$Options.host))) { return }
    $port = [int]$Options.port
    if (Test-NexusTcpPort '127.0.0.1' $port 900) { return }
    if (Start-NexusPostgreSQLService $port) { return }
    if (Start-NexusPostgreSQLPortable $port) { return }
    throw ("PostgreSQL local nao esta iniciado na porta {0}. O instalador tentou iniciar o servico/instancia local mas nao conseguiu. Inicie o PostgreSQL e tente novamente." -f $port)
}

function Start-NexusEngine([hashtable]$Options, [string]$Action = 'install') {
    Ensure-NexusPostgreSQL $Options $Action
    $node = Get-NexusNode
    $Options.action = $Action
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $node
    $info.Arguments = '"' + (Join-Path $PSScriptRoot 'install.mjs') + '"'
    $info.WorkingDirectory = $script:NexusSource
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process; $process.StartInfo = $info; $null = $process.Start()
    $outputTask = $process.StandardOutput.ReadToEndAsync(); $errorTask = $process.StandardError.ReadToEndAsync()
    try { $payload = $Options | ConvertTo-Json -Depth 8 -Compress; $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload); $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $process.StandardInput.Close() }
    finally { $payload = $null; $bytes = $null }
    return [pscustomobject]@{ Process=$process; OutputTask=$outputTask; ErrorTask=$errorTask; Action=$Action }
}
function Complete-NexusEngine($Job) {
    $Job.Process.WaitForExit()
    try {
        $raw = $Job.OutputTask.GetAwaiter().GetResult()
        $null = $Job.ErrorTask.GetAwaiter().GetResult()
        try { $result = $raw | ConvertFrom-Json -ErrorAction Stop } catch { throw 'Motor de instalacao indisponivel. Verifique Node.js e dependencias na origem.' }
        if (-not $result.ok) {
            if ($result.recovery -and $result.destination) {
                Save-NexusProtectedConfig (Join-Path $result.destination '.runtime\recovery.dpapi') $result.recovery -Overwrite
                throw ($result.error + ' Chave de recuperacao protegida em .runtime\recovery.dpapi; nao eliminar a BD.')
            }
            throw $result.error
        }
        if ($Job.Action -eq 'install') {
            Save-NexusProtectedConfig (Join-Path $result.destination '.runtime\config.dpapi') $result -Overwrite
            return [pscustomobject]@{ ok=$true; destination=$result.destination; mode=$result.mode; reportPath=$result.reportPath; warnings=$result.warnings }
        }
        return $result
    } finally { $raw=$null; $result=$null; $Job.Process.Dispose() }
}
function Invoke-NexusEngine([hashtable]$Options, [string]$Action = 'install') { $job = Start-NexusEngine $Options $Action; return Complete-NexusEngine $job }
function ConvertFrom-NexusSecret([securestring]$Secret) { $credential = New-Object System.Management.Automation.PSCredential('secret', $Secret); return $credential.GetNetworkCredential().Password }
