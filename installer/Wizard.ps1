param([switch]$TestMode, [switch]$NoShow)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Install.Common.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:pageIndex=0; $script:connectionValid=$false; $script:engineJob=$null; $script:installResult=$null; $script:importedKey=$null; $script:destinationState='new'; $script:replaceDatabase=$false
$script:modeNames=@('Instalacao Completa','Apenas Base de Dados','Apenas Aplicacao')
$script:modeCodes=@('complete','database','application')
$script:titles=@('Bem-vindo','Tipo de instalacao','Configuracao','Confirmacao','Progresso','Concluido')
$script:form=New-Object System.Windows.Forms.Form
$form.Text='NEXUS-CUP V1.0 - Instalador'; $form.ClientSize=New-Object System.Drawing.Size(790,650)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
$form.Font=New-Object System.Drawing.Font('Segoe UI',10)
$form.BackColor=[System.Drawing.Color]::White
function New-NexusLabel($Parent,[string]$Text,[int]$X,[int]$Y,[int]$Width=680,[int]$Height=32) {
    $label=New-Object System.Windows.Forms.Label; $label.Text=$Text; $label.SetBounds($X,$Y,$Width,$Height); $Parent.Controls.Add($label); return $label
}
function New-NexusButton($Parent,[string]$Text,[int]$X,[int]$Y,[int]$Width=140) {
    $button=New-Object System.Windows.Forms.Button; $button.Text=$Text; $button.SetBounds($X,$Y,$Width,34); $Parent.Controls.Add($button); return $button
}
function New-NexusField($Parent,[string]$Label,[int]$Y,[string]$Value='',[bool]$Secret=$false) {
    $null=New-NexusLabel $Parent $Label 12 $Y 205
    $field=New-Object System.Windows.Forms.TextBox; $field.SetBounds(222,$Y,455,28); $field.Text=$Value; $field.UseSystemPasswordChar=$Secret; $Parent.Controls.Add($field); return $field
}
$script:heading=New-NexusLabel $form '' 24 20 740 40
$heading.Font=New-Object System.Drawing.Font('Segoe UI',18,[System.Drawing.FontStyle]::Bold)
$script:pages=@()
for($i=0;$i -lt 6;$i++){ $panel=New-Object System.Windows.Forms.Panel; $panel.SetBounds(24,76,742,486); $panel.Visible=$false; $form.Controls.Add($panel); $script:pages+=,$panel }
$script:back=New-NexusButton $form 'Anterior' 340 594 125
$script:next=New-NexusButton $form 'Seguinte' 476 594 125
$script:cancel=New-NexusButton $form 'Cancelar' 612 594 150
$script:status=New-NexusLabel $form '' 24 558 738 32
$status.ForeColor=[System.Drawing.Color]::DarkSlateBlue

$null=New-NexusLabel $pages[0] 'Instale NEXUS-CUP V1.0 neste computador ou prepare uma BD para uso posterior.' 12 25 700 65
$null=New-NexusLabel $pages[0] 'Requisitos: Windows, Node.js 22+ e um servidor PostgreSQL acessivel com pgcrypto disponivel. As dependencias Node em falta sao instaladas a partir do lockfile.' 12 108 700 95
$null=New-NexusLabel $pages[0] 'O destino pode ser novo ou uma instalacao NEXUS-CUP existente. Ficheiros da aplicacao podem ser atualizados. Se a BD indicada ja existir, o assistente pede confirmacao explicita antes de a repor de raiz. O servidor PostgreSQL remoto e configurado pelo seu administrador.' 12 220 700 90
$null=New-NexusLabel $pages[0] 'A configuracao final e protegida com DPAPI para este utilizador e computador Windows.' 12 330 700 60
$script:mode=New-Object System.Windows.Forms.ComboBox
$mode.DropDownStyle='DropDownList'; $mode.SetBounds(12,36,685,32); $mode.Items.AddRange($modeNames); $mode.SelectedIndex=0; $pages[1].Controls.Add($mode)
$null=New-NexusLabel $pages[1] "Completa: aplicacao + BD integral nova.`r`n`r`nApenas BD: schemas, regras, roles, auditoria e dados essenciais dos SQL oficiais.`r`n`r`nApenas Aplicacao: liga a uma BD NEXUS-CUP existente, sem a recriar." 12 105 700 180
$null=New-NexusLabel $pages[1] 'Apenas Aplicacao requer importar o config.dpapi da instalacao da BD (mesmo utilizador/computador Windows), evitando pedir segredos forenses ao utilizador.' 12 320 700 95
$script:destination=New-NexusField $pages[2] 'Destino' 8 'C:\temp\NEXUSCUP'
$destination.Width=342
$script:browse=New-NexusButton $pages[2] 'Procurar' 576 5 125
$script:hostField=New-NexusField $pages[2] 'Host PostgreSQL' 49 'localhost'
$script:portField=New-NexusField $pages[2] 'Porta' 90 '5432'
$script:databaseField=New-NexusField $pages[2] 'Base de dados' 131 'nexuscup'
$script:userField=New-NexusField $pages[2] 'Utilizador PostgreSQL' 172 'postgres'
$script:passwordField=New-NexusField $pages[2] 'Password (protegida)' 213 '' $true
$script:importButton=New-NexusButton $pages[2] 'Importar config.dpapi' 222 254 225
$script:testButton=New-NexusButton $pages[2] 'Testar ligacao' 460 254 216
$script:configHint=New-NexusLabel $pages[2] '' 12 305 705 145
$script:summary=New-NexusLabel $pages[3] '' 12 10 710 300
$null=New-NexusLabel $pages[3] 'Use apenas credenciais autorizadas. Password e chave nao sao apresentadas neste resumo. A instalacao nao configura pg_hba.conf, listen_addresses ou firewall.' 12 325 705 90
$script:progressLabel=New-NexusLabel $pages[4] 'A copiar componentes e validar a instalacao. Aguarde...' 12 65 705 90
$script:progress=New-Object System.Windows.Forms.ProgressBar; $progress.SetBounds(12,185,690,30); $progress.Style='Marquee'; $pages[4].Controls.Add($progress)
$null=New-NexusLabel $pages[4] 'Nao feche esta janela durante a instalacao. Uma BD existente so e reposta quando essa acao foi confirmada explicitamente no assistente.' 12 250 700 80
$script:finished=New-NexusLabel $pages[5] '' 12 12 705 260
$script:openApp=New-NexusButton $pages[5] 'Abrir NEXUS-CUP' 12 290 230
$script:openReport=New-NexusButton $pages[5] 'Abrir Relatorio Tecnico' 260 290 260

function Get-NexusWizardOptions {
    $pgPort=0
    if(-not [int]::TryParse($portField.Text,[ref]$pgPort)){throw 'Indicar uma porta numerica.'}
    return @{mode=$modeCodes[$mode.SelectedIndex];destination=$destination.Text;host=$hostField.Text.Trim();port=$pgPort;database=$databaseField.Text.Trim();user=$userField.Text.Trim();password=$passwordField.Text;key=$script:importedKey;replaceDatabase=[bool]$script:replaceDatabase;test=[bool]$TestMode}
}
function Update-NexusNavigation {
    $busy=$null -ne $script:engineJob
    $back.Enabled=(-not $busy -and $pageIndex -gt 0 -and $pageIndex -lt 4)
    $next.Enabled=(-not $busy -and $pageIndex -ne 4 -and -not ($pageIndex -eq 2 -and $mode.SelectedIndex -eq 2 -and -not $connectionValid))
    $next.Text=if($pageIndex -eq 3){if($script:replaceDatabase){'Repor BD / Instalar'}elseif($script:destinationState -eq 'nexuscup'){'Repor / Atualizar'}elseif($script:destinationState -eq 'nonempty'){'Instalar / Substituir'}else{'Instalar'}}elseif($pageIndex -eq 5){'Fechar'}else{'Seguinte'}
    $cancel.Enabled=-not $busy; $pages[2].Enabled=-not $busy
}
function Set-NexusPage([int]$Index) {
    $script:pageIndex=$Index
    for($i=0;$i -lt $pages.Count;$i++){ $pages[$i].Visible=($i -eq $Index) }
    $heading.Text=('{0}/6 - {1}' -f ($Index+1),$titles[$Index])
    if($Index -eq 2){
        $appOnly=$mode.SelectedIndex -eq 2; $importButton.Enabled=$appOnly; $testButton.Enabled=$appOnly
        $configHint.Text=if($appOnly){'Importe config.dpapi da instalacao da BD e depois teste a ligacao. A chave forense e usada internamente e nao e pedida ao utilizador. Host pode ser localhost, hostname ou IP remoto.'}else{'Conta PostgreSQL com permissao para criar BD, roles e pgcrypto. Se o PostgreSQL local estiver parado, o instalador tenta inicia-lo automaticamente. A chave e a conta runtime restrita sao geradas automaticamente. O PDF ausente apenas gera um aviso.'}
    }
    Update-NexusNavigation
}
function Invalidate-NexusConnection { $script:connectionValid=$false; $script:destinationState='new'; $script:replaceDatabase=$false; $status.Text=''; Update-NexusNavigation }
foreach($field in @($destination,$hostField,$portField,$databaseField,$userField,$passwordField)){ $field.Add_TextChanged({ Invalidate-NexusConnection }) }
$mode.Add_SelectedIndexChanged({ Invalidate-NexusConnection })
function Import-NexusWizardConfig([string]$Path) {
    $config=Read-NexusProtectedConfig $Path
    $hostField.Text=if($config.host){$config.host}else{'localhost'}; $portField.Text=[string]$config.port
    $databaseField.Text=$config.database; $userField.Text=$config.user; $passwordField.Text=$config.password; $script:importedKey=$config.key
    $status.Text='Configuracao importada. Teste a ligacao antes de continuar.'; $config=$null
}
$browse.Add_Click({
    $dialog=New-Object System.Windows.Forms.FolderBrowserDialog; $dialog.Description='Selecionar destino da instalacao NEXUS-CUP'; $dialog.ShowNewFolderButton=$true
    try{if($dialog.ShowDialog($form) -eq 'OK'){$destination.Text=$dialog.SelectedPath}}finally{$dialog.Dispose()}
})
$importButton.Add_Click({
    $dialog=New-Object System.Windows.Forms.OpenFileDialog; $dialog.Filter='Configuracao protegida (*.dpapi)|*.dpapi'
    try{if($dialog.ShowDialog($form) -eq 'OK'){Import-NexusWizardConfig $dialog.FileName}}catch{$status.Text=$_.Exception.Message}finally{$dialog.Dispose()}
})
$script:timer=New-Object System.Windows.Forms.Timer; $timer.Interval=120
function Start-NexusWizardJob([string]$Action) {
    try{
        $options=Get-NexusWizardOptions
        if($mode.SelectedIndex -eq 2 -and [string]::IsNullOrWhiteSpace([string]$script:importedKey)){ throw 'No modo Apenas Aplicacao, importe primeiro um config.dpapi valido.' }
        $status.Text=if($Action -eq 'check'){'A testar ligacao e compatibilidade...'}elseif($Action -eq 'plan'){'A verificar configuracao...'}else{'Instalacao em curso...'}
        $script:engineJob=Start-NexusEngine $options $Action
        if($Action -eq 'install'){Set-NexusPage 4}; Update-NexusNavigation; $timer.Start()
    }catch{$status.Text=$_.Exception.Message;Update-NexusNavigation}
}
$timer.Add_Tick({
    if($null -eq $script:engineJob -or -not $script:engineJob.Process.HasExited){return}
    $timer.Stop(); $job=$script:engineJob; $script:engineJob=$null
    try{
        $result=Complete-NexusEngine $job
        switch($job.Action){
            'check' { $script:connectionValid=$true; $status.Text=$result.message }
            'plan' {
                $script:destinationState=[string]$result.destinationState
                $script:replaceDatabase=$false
                if($result.databaseExists -and $mode.SelectedIndex -ne 2){
                    $dbAnswer=[System.Windows.Forms.MessageBox]::Show(
                        $form,
                        ("A base de dados '{0}' ja existe.`r`n`r`nREPOR A BD vai eliminar esta base de dados e cria-la novamente de raiz com os SQL oficiais NEXUS-CUP.`r`n`r`nEsta operacao elimina os dados existentes nessa BD. Nenhuma outra base de dados sera tocada.`r`n`r`nPretende REPOR esta BD e continuar?" -f $result.database),
                        'NEXUS-CUP V1.0 - Repor Base de Dados',
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    if($dbAnswer -ne [System.Windows.Forms.DialogResult]::Yes){
                        $status.Text='Reposicao da BD nao autorizada. Altere o nome da BD ou cancele a instalacao.'
                        $script:destinationState='new'
                        break
                    }
                    $script:replaceDatabase=$true
                }
                if($script:destinationState -eq 'nexuscup'){
                    $answer=[System.Windows.Forms.MessageBox]::Show(
                        $form,
                        "Ja existe uma instalacao NEXUS-CUP neste destino.`r`n`r`nAo continuar, os ficheiros do produto serao repostos/atualizados. A configuracao .runtime sera preservada quando possivel. A base de dados so sera reposta se essa reposicao tiver sido confirmada explicitamente neste assistente.`r`n`r`nPretende avancar?",
                        'NEXUS-CUP V1.0 - Repor / Atualizar',
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    if($answer -ne [System.Windows.Forms.DialogResult]::Yes){
                        $status.Text='Operacao cancelada. A instalacao existente nao foi alterada.'
                        $script:destinationState='new'
                        break
                    }
                }elseif($script:destinationState -eq 'nonempty'){
                    $answer=[System.Windows.Forms.MessageBox]::Show(
                        $form,
                        "A pasta de destino ja contem outros ficheiros.`r`n`r`nAo continuar, ficheiros com os mesmos nomes dos componentes NEXUS-CUP poderao ser substituidos. Os restantes ficheiros serao preservados.`r`n`r`nPretende avancar?",
                        'NEXUS-CUP V1.0 - Destino nao vazio',
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    if($answer -ne [System.Windows.Forms.DialogResult]::Yes){
                        $status.Text='Operacao cancelada. Escolha outro destino ou confirme a substituicao.'
                        $script:destinationState='new'
                        break
                    }
                }
                $summary.Text=('Modo: {0}`r`nDestino: {1}`r`nHost: {2}`r`nPorta: {3}`r`nBD: {4}`r`nUtilizador: {5}' -f $modeNames[$mode.SelectedIndex],$result.destination,$result.host,$result.port,$result.database,$result.user).Replace('`r`n',"`r`n")
                if($script:destinationState -eq 'nexuscup'){ $summary.Text+="`r`n`r`nREINSTALACAO: os ficheiros NEXUS-CUP serao repostos/atualizados. .runtime sera preservado quando possivel." }
                elseif($script:destinationState -eq 'nonempty'){ $summary.Text+="`r`n`r`nSUBSTITUICAO AUTORIZADA: ficheiros NEXUS-CUP com o mesmo nome poderao ser substituidos; outros ficheiros permanecem." }
                if($script:replaceDatabase){ $summary.Text+="`r`n`r`nREPOSICAO DA BD AUTORIZADA: a BD '$($result.database)' sera eliminada e recriada de raiz." }
                if($result.warnings){ foreach($warning in @($result.warnings)){ $summary.Text+="`r`n`r`nAVISO: "+$warning } }
                elseif($result.reportPresent){ $summary.Text+="`r`n`r`nRelatorio PDF: sera copiado." }
                $status.Text=if($script:replaceDatabase){'Reposicao da BD confirmada. Repor BD / Instalar inicia a operacao.'}elseif($script:destinationState -eq 'nexuscup'){'Reinstalacao confirmada. Repor / Atualizar inicia a operacao.'}elseif($script:destinationState -eq 'nonempty'){'Substituicao confirmada. Instalar / Substituir inicia a operacao.'}else{'Configuracao pronta. Instalar inicia a operacao.'}
                Set-NexusPage 3
            }
            'install' {
                $script:installResult=$result; $status.Text='Instalacao concluida.'
                $finished.Text="NEXUS-CUP V1.0 instalado em:`r`n"+$result.destination+"`r`n`r`nConfiguracao protegida em .runtime\config.dpapi."
                if($result.mode -eq 'database'){$finished.Text+="`r`nUse essa configuracao na futura instalacao Apenas Aplicacao."}
                if(-not $result.reportPath){$finished.Text+="`r`n`r`nRelatorio PDF ausente; instalacao concluida sem esse ficheiro."}
                $openApp.Visible=$result.mode -ne 'database'; $openReport.Visible=[bool]$result.reportPath
                $passwordField.Clear();Set-NexusPage 5
            }
        }
    }catch{
        $status.Text=$_.Exception.Message
        if($job.Action -eq 'install'){
            $finished.Text="Instalacao nao concluida.`r`n`r`n"+$_.Exception.Message+"`r`n`r`nNao elimine os dados criados. Escolha Fechar e reveja a configuracao."
            $openApp.Visible=$false;$openReport.Visible=$false;Set-NexusPage 5
        }else{$script:connectionValid=$false}
    }finally{Update-NexusNavigation}
})
$testButton.Add_Click({ Start-NexusWizardJob 'check' })
$back.Add_Click({if($pageIndex -gt 0 -and $pageIndex -lt 4){Set-NexusPage ($pageIndex-1)}})
$next.Add_Click({
    switch($pageIndex){
        0 {Set-NexusPage 1}
        1 {Set-NexusPage 2}
        2 {if($mode.SelectedIndex -ne 2 -or $connectionValid){Start-NexusWizardJob 'plan'}}
        3 {Start-NexusWizardJob 'install'}
        5 {$form.Close()}
    }
})
$cancel.Add_Click({$form.Close()})
$openApp.Add_Click({
    try{
        $starter=Join-Path $installResult.destination 'installer\Start.ps1'
        $proc=Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$starter+'"') -WindowStyle Hidden -Wait -PassThru
        if($proc.ExitCode -ne 0){$status.Text='A aplicacao nao arrancou. Execute INICIAR.cmd no destino para ver o erro.'}
        else{$status.Text='NEXUS-CUP iniciada no browser.'}
    }catch{$status.Text='Nao foi possivel abrir a aplicacao. Execute INICIAR.cmd no destino para ver o erro.'}
})
$openReport.Add_Click({try{Start-Process -FilePath $installResult.reportPath}catch{$status.Text='Nao foi possivel abrir o PDF. Abra o ficheiro no destino.'}})
$form.Add_FormClosing({param($sender,$eventArgs) if($null -ne $script:engineJob){$eventArgs.Cancel=$true;$status.Text='Aguarde a conclusao da operacao em curso.'}})
$form.Add_FormClosed({$timer.Stop();$timer.Dispose();$passwordField.Clear();$script:importedKey=$null})
Set-NexusPage 0
if(-not $NoShow){[void]$form.ShowDialog();$form.Dispose()}
