$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $workspace
$outcome=@()
function Assert-Smoke([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Pump-Smoke { [System.Windows.Forms.Application]::DoEvents() }
function Wait-NexusIdle {
    $deadline=[DateTime]::UtcNow.AddSeconds(35)
    while($null -ne $script:engineJob -and [DateTime]::UtcNow -lt $deadline){Pump-Smoke;Start-Sleep -Milliseconds 40}
    Pump-Smoke
    Assert-Smoke ($null -eq $script:engineJob) 'Motor nao terminou dentro do tempo do smoke.'
}
try {
    foreach($file in @('Install.ps1','Install.Common.ps1','Wizard.ps1','Start.ps1')){
        $tokens=$null;$parseErrors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $workspace ('installer\'+$file)),[ref]$tokens,[ref]$parseErrors)
        Assert-Smoke ($parseErrors.Count -eq 0) ('Sintaxe PowerShell: '+$file)
    }
    & node --check installer/install.mjs
    Assert-Smoke ($LASTEXITCODE -eq 0) 'Sintaxe Node do instalador.'
    & node --check backend/config.mjs
    Assert-Smoke ($LASTEXITCODE -eq 0) 'Sintaxe da configuracao de arranque.'
    . (Join-Path $workspace 'installer\Wizard.ps1') -NoShow -TestMode
    $form.Show();Pump-Smoke
    Assert-Smoke ($form.Visible -and $pages.Count -eq 6) 'Wizard deve abrir com seis ecras.'
    Assert-Smoke ($destination.Text -eq 'C:\temp\NEXUSCUP' -and $hostField.Text -eq 'localhost' -and $portField.Text -eq '5432' -and $databaseField.Text -eq 'nexuscup') 'Defaults incorretos.'
    Assert-Smoke ($passwordField.UseSystemPasswordChar -and $keyField.UseSystemPasswordChar) 'Segredos devem estar mascarados.'
    $next.PerformClick();Pump-Smoke;Assert-Smoke ($pageIndex -eq 1 -and $mode.Items.Count -eq 3) 'Selecao dos tres modos.'
    $smokeRoot=Join-Path $workspace ('.runtime\installer-gui-'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    foreach($index in @(0,1)){
        $mode.SelectedIndex=$index;$next.PerformClick();Pump-Smoke
        Assert-Smoke ($pageIndex -eq 2 -and -not $testButton.Enabled) 'Configuracao Completa/BD.'
        $destination.Text=Join-Path $smokeRoot ('mode-'+$index)
        $next.PerformClick();Wait-NexusIdle
        Assert-Smoke ($pageIndex -eq 3 -and $next.Text -eq 'Instalar') ('Confirmacao nao atingida: '+$status.Text)
        Assert-Smoke ($summary.Text.Contains('PDF ausente') -and -not $summary.Text.Contains('Password:')) 'Aviso do PDF ou resumo incorreto.'
        $back.PerformClick();Pump-Smoke;Assert-Smoke ($pageIndex -eq 2) 'Anterior para configuracao.'
        $back.PerformClick();Pump-Smoke;Assert-Smoke ($pageIndex -eq 1) 'Anterior para tipo.'
    }
    $mode.SelectedIndex=2;$next.PerformClick();Pump-Smoke
    Assert-Smoke ($pageIndex -eq 2 -and $testButton.Enabled -and -not $next.Enabled) 'Aplicacao exige teste antes de Seguinte.'
    $fixture=Get-Content -LiteralPath '.runtime\season-close.json' -Raw | ConvertFrom-Json
    $fixture | Add-Member -NotePropertyName product -NotePropertyValue 'NEXUS-CUP' -Force
    $fixture | Add-Member -NotePropertyName host -NotePropertyValue 'localhost' -Force
    $fixture | Add-Member -NotePropertyName port -NotePropertyValue 55432 -Force
    $configPath=Join-Path $smokeRoot 'source.dpapi'
    Save-NexusProtectedConfig $configPath $fixture
    Import-NexusWizardConfig $configPath
    Assert-Smoke ($passwordField.Text -eq $fixture.password -and $keyField.Text -eq $fixture.key) 'Roundtrip DPAPI.'
    $fixture=$null
    $destination.Text=Join-Path $smokeRoot 'application'
    $databaseField.Text='nexuscup_missing_smoke_database'
    $testButton.PerformClick();Wait-NexusIdle
    Assert-Smoke (-not $connectionValid -and -not $next.Enabled) 'Ligacao invalida nao pode permitir avancar.'
    Import-NexusWizardConfig $configPath
    $testButton.PerformClick();Wait-NexusIdle
    Assert-Smoke ($connectionValid -and $next.Enabled) ('Teste de ligacao falhou: '+$status.Text)
    $databaseField.Text+='x';Pump-Smoke
    Assert-Smoke (-not $connectionValid -and -not $next.Enabled) 'Alterar campos deve invalidar teste.'
    Import-NexusWizardConfig $configPath
    $testButton.PerformClick();Wait-NexusIdle
    Assert-Smoke ($connectionValid) 'Ligacao final nao validada.'
    $next.PerformClick();Wait-NexusIdle
    Assert-Smoke ($pageIndex -eq 3 -and $next.Text -eq 'Instalar') 'Apenas Aplicacao chega a confirmacao.'
    Assert-Smoke (-not $summary.Text.Contains($passwordField.Text) -and -not $summary.Text.Contains($keyField.Text)) 'Resumo expoe segredo.'
    New-Item -ItemType Directory -Path 'test-results' -Force | Out-Null
    $bitmap=New-Object System.Drawing.Bitmap($form.Width,$form.Height)
    try{$form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save((Join-Path $workspace 'test-results\installer-gui.png'),[System.Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $outcome+=@{name='GUI WinForms: arranque, 3 modos, defaults, navegacao, DPAPI, ligacao real, PDF ausente e confirmacao sem instalar';result='PASS'}
    Write-Output 'PASS GUI: seis ecras, tres modos, navegacao, DPAPI, ligacao, PDF ausente; nenhuma instalacao executada.'
}catch{
    $outcome+=@{name='Smoke GUI';result='FAIL';error=$_.Exception.Message}
    Write-Output ('FAIL GUI: '+$_.Exception.Message)
    $global:LASTEXITCODE=1
}finally{
    if($form -and $null -eq $script:engineJob){$form.Close();$form.Dispose()}
    New-Item -ItemType Directory -Path 'test-results' -Force | Out-Null
    ConvertTo-Json -InputObject @($outcome) -Depth 5 | Set-Content -LiteralPath 'test-results\installer-gui-smoke.json' -Encoding UTF8
}
if($outcome.result -contains 'FAIL'){exit 1}
