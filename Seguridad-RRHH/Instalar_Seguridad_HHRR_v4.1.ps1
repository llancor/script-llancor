$ErrorActionPreference = 'Stop'
$RepoUrl = if ($env:SEGURIDAD_REPO_URL) { $env:SEGURIDAD_REPO_URL } else { 'https://github.com/llancor/script-llancor.git' }
$InstallRoot = if ($env:SEGURIDAD_INSTALL_DIR) { $env:SEGURIDAD_INSTALL_DIR } else { Join-Path $env:USERPROFILE 'seguridad-rrhh' }
$ProjectSubdir = 'Seguridad-RRHH'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = if (Test-Path (Join-Path $InstallRoot 'docker-compose.yml')) { $InstallRoot } else { $ScriptDir }

function Write-Title {
    Clear-Host
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '  Seguridad RRHH - Administrador Windows' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host
}
function Pause-Menu { Write-Host; Read-Host 'Presiona Enter para continuar' | Out-Null }
function Write-Option([string]$Number,[string]$Text) { Write-Host "  $Number)" -ForegroundColor Yellow -NoNewline; Write-Host " $Text" -ForegroundColor Cyan }
function Project-Ready { Test-Path (Join-Path $script:AppDir 'docker-compose.yml') }
function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host 'Docker no está instalado.' -ForegroundColor Red; return $false }
    try { docker info *> $null; return $LASTEXITCODE -eq 0 } catch { Write-Host 'Docker Desktop no está iniciado.' -ForegroundColor Red; return $false }
}
function Invoke-Compose { param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args) Push-Location $script:AppDir; try { & docker compose @Args } finally { Pop-Location } }
function New-Secret([int]$Bytes=32) { $buffer=New-Object byte[] $Bytes; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer); -join ($buffer|ForEach-Object{$_.ToString('x2')}) }
function Set-EnvValue([string]$Key,[string]$Value) {
    $file=Join-Path $script:AppDir '.env'; $lines=if(Test-Path $file){[Collections.Generic.List[string]](Get-Content $file)}else{[Collections.Generic.List[string]]::new()}
    $found=$false
    for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match "^$([regex]::Escape($Key))="){$lines[$i]="$Key=$Value";$found=$true}}
    if(-not $found){$lines.Add("$Key=$Value")}
    [IO.File]::WriteAllLines($file,$lines,[Text.UTF8Encoding]::new($false))
}
function Get-EnvValue([string]$Key,[string]$Default='') {
    $file=Join-Path $script:AppDir '.env'; if(Test-Path $file){$line=Get-Content $file|Where-Object{$_ -match "^$([regex]::Escape($Key))="}|Select-Object -Last 1;if($line){return ($line -split '=',2)[1]}};return $Default
}
function Initialize-Env {
    $file=Join-Path $script:AppDir '.env'; if(Test-Path $file){return}
    $template=Join-Path $script:AppDir '.env.docker.example'
    if(Test-Path $template){Copy-Item $template $file}else{[IO.File]::WriteAllLines($file,@('MYSQL_PASSWORD=','MYSQL_ROOT_PASSWORD=','JWT_SECRET=','APP_URL=http://localhost:8080','HTTP_PORT=8080','GOOGLE_CLIENT_ID=','SMTP_HOST=','SMTP_PORT=587','SMTP_USER=','SMTP_PASS=','MAIL_FROM=Seguridad <no-reply@seguridad.local>'),[Text.UTF8Encoding]::new($false))}
    Set-EnvValue MYSQL_PASSWORD (New-Secret 24);Set-EnvValue MYSQL_ROOT_PASSWORD (New-Secret 24);Set-EnvValue JWT_SECRET (New-Secret 48);Set-EnvValue INITIAL_ADMIN_EMAIL 'admin@seguridad.cl';Set-EnvValue INITIAL_ADMIN_PASSWORD (New-Secret 12);Set-EnvValue HTTP_PORT '8080';Set-EnvValue APP_URL 'http://localhost:8080'
}
function Install-Dependencies {
    Write-Title;Write-Host 'Instalando dependencias...' -ForegroundColor Cyan
    if(-not (Get-Command winget -ErrorAction SilentlyContinue)){Write-Host 'Winget no está disponible. Instala App Installer desde Microsoft Store.' -ForegroundColor Red;return}
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements}
    if(-not (Get-Command wsl -ErrorAction SilentlyContinue)){Write-Host 'Instalando WSL 2; Windows puede solicitar un reinicio.' -ForegroundColor Yellow;wsl --install}
    if(-not (Get-Command docker -ErrorAction SilentlyContinue)){winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements;Write-Host 'Docker Desktop instalado. Reinicia Windows si se solicita y abre Docker Desktop.' -ForegroundColor Yellow}else{Write-Host 'Docker ya está instalado.' -ForegroundColor Green}
}
function Copy-ProjectToInstallRoot {
    param([Parameter(Mandatory=$true)][string]$SourceDir)

    if(-not (Test-Path (Join-Path $SourceDir 'docker-compose.yml'))){
        Write-Host "No se encontró $ProjectSubdir/docker-compose.yml en GitHub." -ForegroundColor Red
        return $false
    }

    if(-not (Test-Path $InstallRoot)){
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    }

    $envBackup = $null
    $envFile = Join-Path $InstallRoot '.env'
    if(Test-Path $envFile){
        $envBackup = Join-Path $env:TEMP ("seguridad-env-" + [guid]::NewGuid().ToString('N') + '.bak')
        Copy-Item $envFile $envBackup -Force
    }

    $null = & robocopy $SourceDir $InstallRoot /MIR /XD '.git' /XF '.env' /NFL /NDL /NJH /NJS /NP
    $robocopyCode = $LASTEXITCODE
    if($robocopyCode -gt 7){
        Write-Host "No fue posible copiar el proyecto. Código Robocopy: $robocopyCode" -ForegroundColor Red
        if($envBackup -and (Test-Path $envBackup)){ Remove-Item $envBackup -Force }
        return $false
    }

    if($envBackup -and (Test-Path $envBackup)){
        Copy-Item $envBackup $envFile -Force
        Remove-Item $envBackup -Force
    }

    $script:AppDir = $InstallRoot
    return $true
}

function Get-Project {
    if(Project-Ready){ return $true }
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){
        Write-Host 'Primero instala las dependencias.' -ForegroundColor Red
        return $false
    }

    Write-Host 'Descargando Seguridad RRHH desde GitHub...' -ForegroundColor Cyan
    $tempRoot = Join-Path $env:TEMP ("seguridad-rrhh-" + [guid]::NewGuid().ToString('N'))
    try {
        git clone --depth 1 --filter=blob:none --sparse --branch main $RepoUrl $tempRoot
        if($LASTEXITCODE -ne 0){ return $false }
        git -C $tempRoot sparse-checkout set $ProjectSubdir
        if($LASTEXITCODE -ne 0){ return $false }
        return Copy-ProjectToInstallRoot (Join-Path $tempRoot $ProjectSubdir)
    }
    finally {
        if(Test-Path $tempRoot){ Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
function Show-Url { Initialize-Env;$port=Get-EnvValue HTTP_PORT '8080';$url=Get-EnvValue APP_URL 'http://localhost:8080';Write-Host "URL: $url" -ForegroundColor Cyan;Write-Host "Puerto Docker: $port" -ForegroundColor Cyan;Write-Host "Acceso local: http://localhost:$port" -ForegroundColor Cyan }
function Install-App {
    Write-Title;if(-not (Test-Docker)){Write-Host 'Abre Docker Desktop y espera hasta que indique Engine running.' -ForegroundColor Red;return};if(-not (Get-Project)){return};Initialize-Env
    $current=Get-EnvValue APP_URL 'http://localhost';$url=Read-Host "URL pública [$current]";if($url){Set-EnvValue APP_URL $url}
    Write-Host 'Construyendo y arrancando Seguridad RRHH...' -ForegroundColor Cyan;Invoke-Compose up -d --build
    if($LASTEXITCODE -eq 0){Write-Host 'Seguridad RRHH instalado correctamente.' -ForegroundColor Green;Show-Url}else{Write-Host 'La instalación falló. Revisa los registros.' -ForegroundColor Red;Invoke-Compose logs --tail=100}
}
function Service-Menu { while($true){Write-Title;Write-Host 'ESTADO Y SERVICIOS' -ForegroundColor Cyan;Write-Option 1 'Ver estado';Write-Option 2 'Iniciar';Write-Option 3 'Detener';Write-Option 4 'Reiniciar';Write-Option 5 'Ver registros';Write-Option 6 'Volver';switch(Read-Host 'Opción'){'1'{Invoke-Compose ps;Pause-Menu}'2'{Invoke-Compose up -d;Pause-Menu}'3'{Invoke-Compose stop;Pause-Menu}'4'{Invoke-Compose restart;Pause-Menu}'5'{Invoke-Compose logs --tail=150;Pause-Menu}'6'{return}}} }
function Change-Port { Write-Title;Initialize-Env;$current=Get-EnvValue HTTP_PORT '8080';$port=Read-Host "Nuevo puerto [$current]";if($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535){Write-Host 'Puerto inválido.' -ForegroundColor Red;return};Set-EnvValue HTTP_PORT $port;if((Get-EnvValue APP_URL '') -match '^http://localhost(?::\d+)?$'){Set-EnvValue APP_URL "http://localhost:$port"};Invoke-Compose up -d --force-recreate frontend;Show-Url }
function User-Menu {
    while($true){
        Write-Title;Write-Host 'GESTIÓN DE USUARIOS' -ForegroundColor Cyan
        Write-Option 1 'Listar usuarios';Write-Option 2 'Activar usuario';Write-Option 3 'Desactivar usuario';Write-Option 4 'Cambiar contraseña';Write-Option 5 'Quitar bloqueo por intentos fallidos';Write-Option 6 'Volver'
        $option=Read-Host 'Opción'
        if($option -eq '1'){Invoke-Compose exec -T backend node dist/src/admin-cli.js list-users;Pause-Menu;continue}
        if($option -eq '6'){return}
        if($option -in @('2','3','4','5')){
            Invoke-Compose exec -T backend node dist/src/admin-cli.js list-users;$selected=Read-Host 'Número de usuario'
            if($option -eq '2'){Invoke-Compose exec -T backend node dist/src/admin-cli.js set-enabled $selected true}
            elseif($option -eq '3'){Invoke-Compose exec -T backend node dist/src/admin-cli.js set-enabled $selected false}
            elseif($option -eq '5'){Invoke-Compose exec -T backend node dist/src/admin-cli.js unlock $selected}
            else{$secure=Read-Host 'Nueva contraseña (mínimo 10 caracteres)' -AsSecureString;$ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure);try{$password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)};if($password.Length -lt 10){Write-Host 'Debe tener al menos 10 caracteres.' -ForegroundColor Red}else{Invoke-Compose exec -T backend node dist/src/admin-cli.js reset-password $selected $password}}
            Pause-Menu
        }
    }
}
function Uninstall-App { Write-Title;Write-Option 1 'Quitar contenedores conservando datos';Write-Option 2 'Quitar contenedores y ELIMINAR base de datos';Write-Option 3 'Cancelar';switch(Read-Host 'Opción'){'1'{Invoke-Compose down --remove-orphans}'2'{if((Read-Host 'Escribe ELIMINAR para confirmar') -ceq 'ELIMINAR'){Invoke-Compose down -v --remove-orphans}}} }

function Repair-Database {
    Write-Title
    Write-Host 'Esta operación elimina y vuelve a crear la base de datos de esta instancia.' -ForegroundColor Yellow
    Write-Host 'Se perderán usuarios, guardias, recintos, turnos, rondas y configuraciones actuales.' -ForegroundColor Yellow
    if((Read-Host 'Escribe REPARAR BASE para continuar') -cne 'REPARAR BASE'){Write-Host 'Operación cancelada.';return}
    if(-not (Project-Ready)){Write-Host "No se encontró una instalación válida en $script:AppDir." -ForegroundColor Red;return}
    Initialize-Env
    Invoke-Compose down -v --remove-orphans
    if($LASTEXITCODE -ne 0){return}
    Invoke-Compose up -d --build
    if($LASTEXITCODE -eq 0){Write-Host 'Base de datos reparada e instancia iniciada.' -ForegroundColor Green;Invoke-Compose ps;Show-Url}else{Write-Host 'La reparación falló. Revisa los registros.' -ForegroundColor Red}
}

function Show-InitialCredentials {
    Write-Title
    Write-Host 'Credenciales iniciales' -ForegroundColor Cyan
    Write-Host
    Initialize-Env
    Write-Host 'Usuario: ' -NoNewline;Write-Host (Get-EnvValue INITIAL_ADMIN_EMAIL 'admin@seguridad.cl') -ForegroundColor White
    Write-Host 'Contraseña temporal: ' -NoNewline;Write-Host (Get-EnvValue INITIAL_ADMIN_PASSWORD 'No disponible') -ForegroundColor White
    Write-Host
    Write-Host 'Por seguridad, cambia esta contraseña después del primer inicio de sesión.' -ForegroundColor Yellow
}

function Update-App {
    Write-Title
    Write-Host 'Actualizar Seguridad RRHH' -ForegroundColor Cyan
    Write-Host
    if(-not (Test-Docker)){Write-Host 'Abre Docker Desktop y espera hasta que indique Engine running.' -ForegroundColor Red;return}
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){Write-Host 'Git no está instalado. Ejecuta primero la opción 1.' -ForegroundColor Red;return}

    $script:AppDir = $InstallRoot
    if(-not (Project-Ready)){
        Write-Host "No se encontró Seguridad RRHH en $InstallRoot." -ForegroundColor Red
        return
    }

    Write-Host 'Descargando únicamente Seguridad-RRHH desde GitHub...' -ForegroundColor Cyan
    $tempRoot = Join-Path $env:TEMP ("seguridad-rrhh-update-" + [guid]::NewGuid().ToString('N'))
    try {
        git clone --depth 1 --filter=blob:none --sparse --branch main $RepoUrl $tempRoot
        if($LASTEXITCODE -ne 0){Write-Host 'No fue posible descargar la actualización.' -ForegroundColor Red;return}
        git -C $tempRoot sparse-checkout set $ProjectSubdir
        if($LASTEXITCODE -ne 0){Write-Host 'No fue posible seleccionar la carpeta Seguridad-RRHH.' -ForegroundColor Red;return}
        if(-not (Copy-ProjectToInstallRoot (Join-Path $tempRoot $ProjectSubdir))){return}
    }
    finally {
        if(Test-Path $tempRoot){ Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Initialize-Env
    Write-Host 'Reconstruyendo servicios sin borrar la base de datos ni la configuración...' -ForegroundColor Cyan
    Invoke-Compose up -d --build --remove-orphans
    if($LASTEXITCODE -eq 0){Write-Host 'Seguridad RRHH actualizado. La base de datos y el archivo .env se conservaron.' -ForegroundColor Green;Invoke-Compose ps;Show-Url}else{Write-Host 'La actualización falló. Revisa los registros.' -ForegroundColor Red}
}

while($true){Write-Title;Write-Host 'INSTALACIÓN' -ForegroundColor Cyan;Write-Option 1 'Instalar dependencias';Write-Option 2 'Instalar Seguridad RRHH';Write-Host;Write-Host 'ADMINISTRACIÓN' -ForegroundColor Cyan;Write-Option 3 'Estado y control del servicio';Write-Option 4 'Cambiar puerto de Docker';Write-Option 5 'Ver URL y puerto';Write-Option 6 'Gestión de usuarios';Write-Host;Write-Host 'MANTENIMIENTO' -ForegroundColor Cyan;Write-Option 7 'Desinstalar';Write-Option 8 'Reparar base de datos';Write-Option 9 'Ver credenciales iniciales';Write-Option 10 'Actualizar Seguridad RRHH';Write-Option 0 'Salir';switch(Read-Host 'Selecciona una opción'){'1'{Install-Dependencies;Pause-Menu}'2'{Install-App;Pause-Menu}'3'{Service-Menu}'4'{Change-Port;Pause-Menu}'5'{Write-Title;Show-Url;Pause-Menu}'6'{User-Menu}'7'{Uninstall-App;Pause-Menu}'8'{Repair-Database;Pause-Menu}'9'{Show-InitialCredentials;Pause-Menu}'10'{Update-App;Pause-Menu}'0'{exit}}}
