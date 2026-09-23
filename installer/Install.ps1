param(
    [ValidateSet('complete','database','application')][string]$Mode,
    [string]$Destination, [string]$PgHost, [int]$Port,
    [string]$Database, [string]$User, [string]$ConfigSource,
    [switch]$TestMode
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Install.Common.ps1')
function Read-Default([string]$Label, [string]$Default) {
    $answer = Read-Host ($Label + ' [' + $Default + ']')
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }; return $answer
}
try {
    Write-Host 'NEXUS-CUP V1.0 - Instalador em modo texto' -ForegroundColor Cyan
    Write-Host 'Requer Node.js 22+. Para localhost, o instalador tenta iniciar o PostgreSQL se estiver parado. Uma BD existente so e reposta apos confirmacao explicita.'
    if (-not $Mode) {
        Write-Host '1 - Completa | 2 - Apenas Base de Dados | 3 - Apenas Aplicacao'
        $selection = Read-Default 'Tipo' '1'
        $Mode = @{ '1'='complete'; '2'='database'; '3'='application' }[$selection]
        if (-not $Mode) { throw 'Escolher 1, 2 ou 3.' }
    }
    $imported = $null
    if ($Mode -eq 'application') {
        if (-not $ConfigSource) { $ConfigSource = Read-Host 'Configuracao de origem config.dpapi' }
        if (-not $ConfigSource) { throw 'No modo Apenas Aplicacao e obrigatorio importar um config.dpapi valido.' }
        $imported = Read-NexusProtectedConfig $ConfigSource
        Write-Host 'A conta runtime e a chave forense sao lidas do config.dpapi protegido. DPAPI requer o mesmo utilizador/computador Windows.'
    }
    if (-not $Destination) { $Destination = Read-Default 'Destino' 'C:\temp\NEXUSCUP' }
    if (-not $PgHost) { $PgHost = Read-Default 'Host PostgreSQL' $(if ($imported.host) { $imported.host } else { 'localhost' }) }
    if (-not $Port) { $Port = [int](Read-Default 'Porta' $(if ($imported.port) { [string]$imported.port } else { '5432' })) }
    if (-not $Database) { $Database = Read-Default 'Base de dados' $(if ($imported.database) { $imported.database } else { 'nexuscup' }) }
    if (-not $User) { $User = Read-Default 'Utilizador PostgreSQL' $(if ($imported.user) { $imported.user } else { 'postgres' }) }
    $secret = Read-Host 'Password PostgreSQL (protegida; Enter conserva a importada, se existir)' -AsSecureString
    $password = if ($secret.Length -eq 0 -and $imported) { $imported.password } else { ConvertFrom-NexusSecret $secret }
    $key = $imported.key
    $options = @{ mode=$Mode; destination=$Destination; host=$PgHost; port=$Port; database=$Database; user=$User; password=$password; key=$key; test=[bool]$TestMode }
    $plan = Invoke-NexusEngine $options 'plan'
    if ($Mode -ne 'application' -and $plan.databaseExists) {
        Write-Host ("ATENCAO: a BD '{0}' ja existe. REPOR elimina essa BD e recria-a de raiz." -f $Database) -ForegroundColor Yellow
        if ((Read-Host 'Para autorizar a reposicao desta BD, escreva REPOR_BD') -cne 'REPOR_BD') { Write-Host 'Reposicao nao autorizada. Altere o nome da BD ou cancele.'; exit 0 }
        $options.replaceDatabase = $true
    }
    if ($Mode -eq 'application') { $check = Invoke-NexusEngine $options 'check'; Write-Host $check.message -ForegroundColor Green }
    Write-Host ('Modo: {0} | Destino: {1} | PostgreSQL: {2}:{3} | BD: {4} | Utilizador: {5}' -f $Mode,$Destination,$PgHost,$Port,$Database,$User)
    foreach ($warning in $plan.warnings) { Write-Host $warning -ForegroundColor Yellow }
    Write-Host 'Use apenas credenciais autorizadas. A configuracao final fica protegida por DPAPI.'
    if ($plan.destinationState -eq 'nexuscup') {
        Write-Host 'REINSTALACAO: os ficheiros NEXUS-CUP serao repostos/atualizados; .runtime e a BD existente nao serao apagados.' -ForegroundColor Yellow
        if ((Read-Host 'Para continuar, escreva REPOR') -cne 'REPOR') { Write-Host 'Cancelado antes da reinstalacao.'; exit 0 }
    } elseif ($plan.destinationState -eq 'nonempty') {
        Write-Host 'ATENCAO: a pasta contem outros ficheiros. Ficheiros NEXUS-CUP com nomes iguais poderao ser substituidos; os restantes serao preservados.' -ForegroundColor Yellow
        if ((Read-Host 'Para continuar, escreva SUBSTITUIR') -cne 'SUBSTITUIR') { Write-Host 'Cancelado antes da instalacao.'; exit 0 }
    } elseif ((Read-Host 'Instalar agora? Escreva INSTALAR') -cne 'INSTALAR') { Write-Host 'Cancelado antes da instalacao.'; exit 0 }
    Write-Host 'A copiar componentes e validar instalacao. Aguarde...'
    $result = Invoke-NexusEngine $options 'install'
    Write-Host ('Instalacao concluida em ' + $result.destination) -ForegroundColor Green
    if ($Mode -eq 'database') { Write-Host 'Guarde .runtime\config.dpapi: sera usada na instalacao Apenas Aplicacao.' }
    if ($Mode -ne 'database' -and (Read-Host 'Abrir NEXUS-CUP? [s/N]') -eq 's') { & (Join-Path $result.destination 'installer\Start.ps1') }
    if ($result.reportPath -and (Read-Host 'Abrir Relatorio Tecnico? [s/N]') -eq 's') { Start-Process -FilePath $result.reportPath }
    exit 0
} catch { Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
finally { $password=$null; $key=$null; $secret=$null; $options=$null; $imported=$null }
