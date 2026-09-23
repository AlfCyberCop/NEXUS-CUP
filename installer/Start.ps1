param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
. (Join-Path $PSScriptRoot 'Install.Common.ps1')
try {
    $path = Join-Path $root '.runtime\config.dpapi'
    if (-not (Test-Path -LiteralPath $path)) { throw 'Executar INSTALAR.cmd primeiro.' }
    $protected = (Get-Content -LiteralPath $path -Raw).Trim() | ConvertTo-SecureString
    $credential = New-Object System.Management.Automation.PSCredential('config', $protected)
    $settings = $credential.GetNetworkCredential().Password | ConvertFrom-Json
    if ($settings.mode -eq 'database') { throw 'Este destino contem Apenas BD. Instale a aplicacao num destino separado.' }
    if ($settings.port -lt 1 -or $settings.port -gt 65535 -or $settings.port -eq 6666 -or ($settings.port -eq 55432 -and -not $settings.test) -or $settings.appPort -eq 6666) { throw 'Configuracao fora das portas autorizadas.' }
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    $expected = & $node --input-type=module -e "import {root} from './backend/config.mjs'; import {createHash} from 'node:crypto'; console.log(createHash('sha256').update(root).digest('hex').slice(0,16))"
    $expectedBuild = (Get-Content -LiteralPath (Join-Path $root 'BUILD.txt') -Raw).Trim()
    $preferredPort = [int]$settings.appPort
    $url = 'http://127.0.0.1:' + $preferredPort
    $existing = $null
    try { $existing = Invoke-RestMethod -Uri ($url + '/api/health') -TimeoutSec 2 } catch {}
    if ($existing -and $existing.product -eq 'NEXUS-CUP' -and $existing.instance -eq $expected.Trim() -and $existing.build -eq $expectedBuild) {
        Write-Host ('NEXUS-CUP ja disponivel em ' + $url) -ForegroundColor Green
        if (-not $NoBrowser) { Start-Process $url }
        exit 0
    }

    # Se a porta configurada estiver ocupada por outro processo/instancia, escolher
    # automaticamente uma porta livre local e persistir a nova configuracao DPAPI.
    if (Test-NexusTcpPort '127.0.0.1' $preferredPort 500) {
        $selectedPort = $null
        foreach ($candidate in (($preferredPort + 1)..([Math]::Min($preferredPort + 99,65535)))) {
            if ($candidate -eq 6666) { continue }
            if (-not (Test-NexusTcpPort '127.0.0.1' $candidate 250)) { $selectedPort = $candidate; break }
        }
        if ($null -eq $selectedPort) { throw ('Porta da aplicacao {0} ocupada e nao foi encontrada alternativa livre.' -f $preferredPort) }
        $settings.appPort = [int]$selectedPort
        Save-NexusProtectedConfig $path $settings -Overwrite
        Write-Host ('Porta {0} ocupada; NEXUS-CUP vai usar automaticamente a porta {1}.' -f $preferredPort,$selectedPort) -ForegroundColor Yellow
    }
    $url = 'http://127.0.0.1:' + $settings.appPort
    $env:PGHOST=if ($settings.host) { $settings.host } else { 'localhost' }; $env:PGPORT=[string]$settings.port; $env:PGUSER=$settings.user; $env:PGPASSWORD=$settings.password; $env:PGDATABASE=$settings.database
    $env:NEXUS_TEST=if ($settings.test) { '1' } else { $null }
    $env:NEXUS_FORENSIC_KEY=$settings.key; $env:PORT=[string]$settings.appPort
    $stdout = Join-Path $root '.runtime\server.stdout.log'
    $stderr = Join-Path $root '.runtime\server.stderr.log'
    $process = Start-Process -FilePath $node -ArgumentList 'backend/server.js' -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $env:PGPASSWORD=$null; $env:NEXUS_FORENSIC_KEY=$null
    $ready=$false
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 300
        $process.Refresh()
        if ($process.HasExited) { throw ('Servidor terminou. Consulte ' + $stderr) }
        try {
            $health=Invoke-RestMethod -Uri ($url + '/api/health') -TimeoutSec 2
            if ($health.product -eq 'NEXUS-CUP' -and $health.instance -eq $expected.Trim() -and $health.build -eq $expectedBuild -and $health.schema) { $ready=$true; break }
        } catch {}
    }
    if (-not $ready) { throw ('Servidor ainda indisponivel. Consulte ' + $stderr) }
    Write-Host ('NEXUS-CUP V1.0 ' + $expectedBuild + ' validado e disponivel em ' + $url) -ForegroundColor Green
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
} catch {
    Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally { $env:PGPASSWORD=$null; $env:NEXUS_FORENSIC_KEY=$null; $env:NEXUS_TEST=$null }
