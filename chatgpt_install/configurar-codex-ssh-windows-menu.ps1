#requires -Version 5.1

$ErrorActionPreference = 'Stop'

$SshDir = Join-Path $env:USERPROFILE '.ssh'
$ConfigFile = Join-Path $SshDir 'config'
$DefaultKey = Join-Path $SshDir 'id_ed25519'

function Pause-Menu {
    Write-Host ''
    Read-Host 'Presiona ENTER para continuar' | Out-Null
}

function Clear-Menu {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '          ADMINISTRADOR SSH PARA WINDOWS' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Test-CommandExists($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-SshDirectory {
    if (-not (Test-Path $SshDir)) {
        New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
    }
}

function Show-Status {
    Clear-Menu
    Write-Host 'ESTADO DE OPENSSH' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('Cliente ssh:      ' + $(if (Test-CommandExists 'ssh') {'INSTALADO'} else {'NO INSTALADO'}))
    Write-Host ('ssh-keygen:        ' + $(if (Test-CommandExists 'ssh-keygen') {'DISPONIBLE'} else {'NO DISPONIBLE'}))
    Write-Host ('Carpeta .ssh:      ' + $SshDir)
    Write-Host ('Archivo config:    ' + $ConfigFile)
    Write-Host ('Clave por defecto: ' + $DefaultKey)

    if (Test-Path $ConfigFile) {
        Write-Host ''
        Write-Host 'Perfiles configurados:' -ForegroundColor Green
        $hosts = Select-String -Path $ConfigFile -Pattern '^\s*Host\s+(.+)$' -ErrorAction SilentlyContinue
        if ($hosts) {
            foreach ($h in $hosts) {
                Write-Host ('  - ' + $h.Matches[0].Groups[1].Value)
            }
        } else {
            Write-Host '  No se encontraron perfiles.'
        }
    }
    Pause-Menu
}

function Install-OpenSSHClient {
    Clear-Menu
    Write-Host 'INSTALAR CLIENTE OPENSSH' -ForegroundColor Yellow
    Write-Host ''

    if (Test-CommandExists 'ssh') {
        Write-Host 'OpenSSH Client ya esta instalado.' -ForegroundColor Green
        Pause-Menu
        return
    }

    try {
        $cap = Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Client*' | Select-Object -First 1
        if (-not $cap) {
            throw 'No se encontro la caracteristica OpenSSH.Client en Windows.'
        }
        Write-Host 'Instalando OpenSSH Client...'
        Add-WindowsCapability -Online -Name $cap.Name | Out-Host
        Write-Host ''
        Write-Host 'OpenSSH Client instalado.' -ForegroundColor Green
    } catch {
        Write-Host ''
        Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Ejecuta PowerShell como Administrador e intenta nuevamente.' -ForegroundColor Yellow
    }
    Pause-Menu
}

function Read-WithDefault([string]$Prompt, [string]$Default) {
    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Get-HostBlockPattern([string]$Alias) {
    $escaped = [regex]::Escape($Alias)
    return "(?ms)^Host\s+$escaped\s*\r?\n(?:(?!^Host\s+).*(?:\r?\n|$))*"
}

function Remove-HostBlock([string]$Alias) {
    if (-not (Test-Path $ConfigFile)) { return $false }
    $content = Get-Content -Raw -Path $ConfigFile
    $pattern = Get-HostBlockPattern $Alias
    $newContent = [regex]::Replace($content, $pattern, '')
    if ($newContent -ne $content) {
        $newContent = $newContent.Trim() + "`r`n"
        Set-Content -Path $ConfigFile -Value $newContent -Encoding ascii
        return $true
    }
    return $false
}

function Add-OrUpdateHostBlock {
    param(
        [Parameter(Mandatory=$true)][string]$Alias,
        [Parameter(Mandatory=$true)][string]$HostName,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][int]$Port,
        [Parameter(Mandatory=$true)][string]$IdentityFile
    )

    Ensure-SshDirectory
    if (-not (Test-Path $ConfigFile)) {
        New-Item -ItemType File -Path $ConfigFile -Force | Out-Null
    }

    [void](Remove-HostBlock $Alias)

    $identityForConfig = $IdentityFile.Replace($env:USERPROFILE, '~').Replace('\','/')
    $block = @"
Host $Alias
  HostName $HostName
  User $User
  Port $Port
  IdentityFile $identityForConfig
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 3
"@

    $existing = Get-Content -Raw -Path $ConfigFile -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        Add-Content -Path $ConfigFile -Value "`r`n$block" -Encoding ascii
    } else {
        Set-Content -Path $ConfigFile -Value $block -Encoding ascii
    }
}

function Ensure-KeyPair([string]$KeyPath, [string]$Comment) {
    Ensure-SshDirectory
    if (Test-Path $KeyPath) {
        Write-Host ('Usando clave existente: ' + $KeyPath) -ForegroundColor Green
        return
    }

    if (-not (Test-CommandExists 'ssh-keygen')) {
        throw 'ssh-keygen no esta disponible. Instala primero OpenSSH Client.'
    }

    Write-Host ('Creando nueva clave ED25519: ' + $KeyPath) -ForegroundColor Yellow
    & ssh-keygen -t ed25519 -f $KeyPath -C $Comment -N ''
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible generar la clave SSH.' }
}

function Copy-KeyToServer {
    param(
        [string]$HostName,
        [string]$User,
        [int]$Port,
        [string]$KeyPath
    )

    $pubPath = "$KeyPath.pub"
    if (-not (Test-Path $pubPath)) { throw "No existe la clave publica: $pubPath" }

    $pubKey = (Get-Content -Raw $pubPath).Trim()
    $pubKeyB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pubKey))

    Write-Host ''
    Write-Host 'Se pedira la contrasena SSH del servidor una sola vez.' -ForegroundColor Yellow
    Write-Host 'Copiando clave publica al servidor...'

    $remoteCmd = "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; key=`$(printf '%s' '$pubKeyB64' | base64 -d); grep -qxF `"`$key`" ~/.ssh/authorized_keys || printf '%s\n' `"`$key`" >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
    & ssh -p $Port "$User@$HostName" $remoteCmd
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible copiar la clave publica al servidor.' }
}

function Configure-NewProfile {
    Clear-Menu
    Write-Host 'AGREGAR / CONFIGURAR EQUIPO SSH' -ForegroundColor Yellow
    Write-Host ''

    if (-not (Test-CommandExists 'ssh')) {
        Write-Host 'OpenSSH Client no esta instalado. Usa primero la opcion 1.' -ForegroundColor Red
        Pause-Menu
        return
    }

    $alias = Read-Host 'Nombre corto del equipo (ej: core, nas, servidor1)'
    if ([string]::IsNullOrWhiteSpace($alias)) {
        Write-Host 'El nombre del equipo es obligatorio.' -ForegroundColor Red
        Pause-Menu
        return
    }
    $alias = $alias.Trim()

    $hostName = Read-Host 'IP o nombre DNS del servidor'
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        Write-Host 'La IP o nombre DNS es obligatorio.' -ForegroundColor Red
        Pause-Menu
        return
    }
    $hostName = $hostName.Trim()

    $user = Read-WithDefault 'Usuario SSH' 'root'
    $portText = Read-WithDefault 'Puerto SSH' '22'
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        Write-Host 'Puerto invalido.' -ForegroundColor Red
        Pause-Menu
        return
    }

    Write-Host ''
    Write-Host 'Tipo de clave:' -ForegroundColor Cyan
    Write-Host '[1] Usar clave general id_ed25519'
    Write-Host '[2] Crear una clave exclusiva para este equipo'
    $keyOpt = Read-WithDefault 'Opcion' '1'

    if ($keyOpt -eq '2') {
        $safeAlias = ($alias -replace '[^A-Za-z0-9_.-]', '_')
        $keyPath = Join-Path $SshDir "id_ed25519_$safeAlias"
    } else {
        $keyPath = $DefaultKey
    }

    try {
        Ensure-KeyPair -KeyPath $keyPath -Comment "$env:USERNAME@$env:COMPUTERNAME-$alias"
        Copy-KeyToServer -HostName $hostName -User $user -Port $port -KeyPath $keyPath
        Add-OrUpdateHostBlock -Alias $alias -HostName $hostName -User $user -Port $port -IdentityFile $keyPath

        Write-Host ''
        Write-Host 'Configuracion completada.' -ForegroundColor Green
        Write-Host ('Alias:    ' + $alias)
        Write-Host ('Servidor: ' + $hostName)
        Write-Host ('Usuario:  ' + $user)
        Write-Host ('Puerto:   ' + $port)
        Write-Host ('Clave:    ' + $keyPath)
        Write-Host ''
        Write-Host ('Para conectarte usa:  ssh ' + $alias) -ForegroundColor Cyan

        Write-Host ''
        Write-Host 'Probando conexion por clave...' -ForegroundColor Yellow
        & ssh -o BatchMode=yes -o ConnectTimeout=8 $alias 'echo Conexion SSH por clave lista'
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Conexion verificada correctamente.' -ForegroundColor Green
        } else {
            Write-Host 'La configuracion fue guardada, pero la prueba automatica fallo.' -ForegroundColor Yellow
        }
    } catch {
        Write-Host ''
        Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    }
    Pause-Menu
}

function List-Profiles {
    Clear-Menu
    Write-Host 'PERFILES SSH CONFIGURADOS' -ForegroundColor Yellow
    Write-Host ''

    if (-not (Test-Path $ConfigFile)) {
        Write-Host 'No existe el archivo de configuracion SSH.'
        Pause-Menu
        return
    }

    $content = Get-Content -Path $ConfigFile
    $current = $null
    foreach ($line in $content) {
        if ($line -match '^\s*Host\s+(.+)$') {
            if ($current) { Write-Host '' }
            $current = $Matches[1]
            Write-Host ('[' + $current + ']') -ForegroundColor Cyan
        } elseif ($current -and $line -match '^\s*(HostName|User|Port|IdentityFile)\s+(.+)$') {
            Write-Host ('  ' + $Matches[1].PadRight(12) + ': ' + $Matches[2])
        }
    }
    Pause-Menu
}

function Test-ProfileConnection {
    Clear-Menu
    Write-Host 'PROBAR CONEXION SSH' -ForegroundColor Yellow
    Write-Host ''
    $alias = Read-Host 'Alias del equipo'
    if ([string]::IsNullOrWhiteSpace($alias)) { return }

    Write-Host ''
    & ssh -o ConnectTimeout=10 $alias 'echo OK; hostname; whoami'
    Pause-Menu
}

function Open-ConfigFile {
    Ensure-SshDirectory
    if (-not (Test-Path $ConfigFile)) { New-Item -ItemType File -Path $ConfigFile -Force | Out-Null }
    Start-Process notepad.exe $ConfigFile
}

function Delete-Profile {
    Clear-Menu
    Write-Host 'ELIMINAR PERFIL SSH' -ForegroundColor Yellow
    Write-Host ''
    $alias = Read-Host 'Alias que deseas eliminar'
    if ([string]::IsNullOrWhiteSpace($alias)) { return }

    if (Remove-HostBlock $alias.Trim()) {
        Write-Host ('Perfil ' + $alias + ' eliminado del archivo config.') -ForegroundColor Green
        Write-Host 'La clave SSH local NO fue eliminada y la clave remota NO fue revocada.' -ForegroundColor Yellow
    } else {
        Write-Host 'No se encontro ese alias.' -ForegroundColor Red
    }
    Pause-Menu
}

function Revoke-RemoteKey {
    Clear-Menu
    Write-Host 'REVOCAR CLAVE EN SERVIDOR REMOTO' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Esta opcion elimina del servidor una clave publica seleccionada.' -ForegroundColor Yellow

    $hostName = Read-Host 'IP o DNS del servidor'
    $user = Read-WithDefault 'Usuario SSH' 'root'
    $portText = Read-WithDefault 'Puerto SSH' '22'
    $port = [int]$portText
    $keyPath = Read-WithDefault 'Ruta de la clave privada local' $DefaultKey
    $pubPath = "$keyPath.pub"

    if (-not (Test-Path $pubPath)) {
        Write-Host ('No existe: ' + $pubPath) -ForegroundColor Red
        Pause-Menu
        return
    }

    $pubKey = (Get-Content -Raw $pubPath).Trim()
    $pubKeyB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pubKey))
    $cmd = "key=`$(printf '%s' '$pubKeyB64' | base64 -d); tmp=~/.ssh/authorized_keys.tmp; grep -vxF `"`$key`" ~/.ssh/authorized_keys > `$tmp || true; mv `$tmp ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"

    Write-Host ''
    Write-Host 'Puede solicitar la contrasena del servidor si esta clave era la unica autorizada.' -ForegroundColor Yellow
    & ssh -p $port "$user@$hostName" $cmd
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Clave remota revocada.' -ForegroundColor Green
    } else {
        Write-Host 'No fue posible revocar la clave.' -ForegroundColor Red
    }
    Pause-Menu
}

function Show-PublicKey {
    Clear-Menu
    Write-Host 'MOSTRAR CLAVE PUBLICA' -ForegroundColor Yellow
    Write-Host ''
    $keyPath = Read-WithDefault 'Ruta de la clave privada' $DefaultKey
    $pubPath = "$keyPath.pub"
    if (Test-Path $pubPath) {
        Write-Host ''
        Get-Content $pubPath
    } else {
        Write-Host ('No existe: ' + $pubPath) -ForegroundColor Red
    }
    Pause-Menu
}

Ensure-SshDirectory

do {
    Clear-Menu
    Write-Host '[01] Instalar cliente OpenSSH' -ForegroundColor Yellow
    Write-Host '[02] Agregar / configurar equipo SSH' -ForegroundColor Yellow
    Write-Host '[03] Ver equipos configurados' -ForegroundColor Yellow
    Write-Host '[04] Probar conexion a un equipo' -ForegroundColor Yellow
    Write-Host '[05] Editar archivo SSH config' -ForegroundColor Yellow
    Write-Host '[06] Eliminar perfil del config' -ForegroundColor Yellow
    Write-Host '[07] Revocar clave en servidor remoto' -ForegroundColor Yellow
    Write-Host '[08] Mostrar clave publica local' -ForegroundColor Yellow
    Write-Host '[09] Ver estado de OpenSSH' -ForegroundColor Yellow
    Write-Host '[00] Salir' -ForegroundColor Yellow
    Write-Host ''

    $option = Read-Host 'Opcion'
    switch ($option) {
        '1'  { Install-OpenSSHClient }
        '01' { Install-OpenSSHClient }
        '2'  { Configure-NewProfile }
        '02' { Configure-NewProfile }
        '3'  { List-Profiles }
        '03' { List-Profiles }
        '4'  { Test-ProfileConnection }
        '04' { Test-ProfileConnection }
        '5'  { Open-ConfigFile }
        '05' { Open-ConfigFile }
        '6'  { Delete-Profile }
        '06' { Delete-Profile }
        '7'  { Revoke-RemoteKey }
        '07' { Revoke-RemoteKey }
        '8'  { Show-PublicKey }
        '08' { Show-PublicKey }
        '9'  { Show-Status }
        '09' { Show-Status }
        '0'  { }
        '00' { }
        default {
            Write-Host 'Opcion invalida.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($option -notin @('0','00'))

Write-Host ''
Write-Host 'Saliendo del Administrador SSH.' -ForegroundColor Cyan
