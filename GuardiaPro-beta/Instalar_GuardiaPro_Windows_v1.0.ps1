$ErrorActionPreference = 'Stop'
$RepoUrl = if ($env:GUARDIAPRO_REPO_URL) { $env:GUARDIAPRO_REPO_URL } else { 'https://github.com/llancor/script-llancor.git' }
$InstallRoot = if ($env:GUARDIAPRO_INSTALL_DIR) { $env:GUARDIAPRO_INSTALL_DIR } else { Join-Path $env:USERPROFILE 'guardiapro' }
$ProjectSubdir = 'Control_Entrada_Guardia'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = $ScriptDir
if (-not (Test-Path (Join-Path $AppDir 'docker-compose.yml')) -and (Test-Path (Join-Path $InstallRoot "$ProjectSubdir\docker-compose.yml"))) {
    $AppDir = Join-Path $InstallRoot $ProjectSubdir
}

function Write-Title {
    Clear-Host
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '  GuardiaPro - Administrador Windows' -ForegroundColor Cyan
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
    if(Test-Path $template){Copy-Item $template $file}else{[IO.File]::WriteAllLines($file,@('MYSQL_PASSWORD=','MYSQL_ROOT_PASSWORD=','JWT_SECRET=','APP_URL=','HTTP_PORT=80','GOOGLE_CLIENT_ID=','SMTP_HOST=','SMTP_PORT=587','SMTP_USER=','SMTP_PASS=','MAIL_FROM=GuardiaPro <no-reply@guardiapro.local>'),[Text.UTF8Encoding]::new($false))}
    Set-EnvValue MYSQL_PASSWORD (New-Secret 24);Set-EnvValue MYSQL_ROOT_PASSWORD (New-Secret 24);Set-EnvValue JWT_SECRET (New-Secret 48);Set-EnvValue HTTP_PORT '80';Set-EnvValue APP_URL 'http://localhost'
}
function Install-Dependencies {
    Write-Title;Write-Host 'Instalando dependencias...' -ForegroundColor Cyan
    if(-not (Get-Command winget -ErrorAction SilentlyContinue)){Write-Host 'Winget no está disponible. Instala App Installer desde Microsoft Store.' -ForegroundColor Red;return}
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements}
    if(-not (Get-Command wsl -ErrorAction SilentlyContinue)){Write-Host 'Instalando WSL 2; Windows puede solicitar un reinicio.' -ForegroundColor Yellow;wsl --install}
    if(-not (Get-Command docker -ErrorAction SilentlyContinue)){winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements;Write-Host 'Docker Desktop instalado. Reinicia Windows si se solicita y abre Docker Desktop.' -ForegroundColor Yellow}else{Write-Host 'Docker ya está instalado.' -ForegroundColor Green}
}
function Get-Project {
    if(Project-Ready){try{$root=git -C $script:AppDir rev-parse --show-toplevel 2>$null;if($root){Write-Host 'Buscando actualizaciones en GitHub...' -ForegroundColor Cyan;git -C $root pull --ff-only}}catch{};return $true}
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){Write-Host 'Primero instala las dependencias.' -ForegroundColor Red;return $false}
    Write-Host 'Descargando GuardiaPro desde GitHub...' -ForegroundColor Cyan
    if(Test-Path (Join-Path $InstallRoot '.git')){git -C $InstallRoot pull --ff-only}elseif(Test-Path $InstallRoot){Write-Host "La ruta $InstallRoot existe y no es un repositorio Git." -ForegroundColor Red;return $false}else{git clone --depth 1 --branch main $RepoUrl $InstallRoot}
    $script:AppDir=Join-Path $InstallRoot $ProjectSubdir
    if(-not (Project-Ready)){Write-Host 'No se encontró Control_Entrada_Guardia/docker-compose.yml.' -ForegroundColor Red;return $false};return $true
}
function Show-Url { Initialize-Env;$port=Get-EnvValue HTTP_PORT '80';$url=Get-EnvValue APP_URL 'http://localhost';Write-Host "URL: $url" -ForegroundColor Cyan;Write-Host "Puerto Docker: $port" -ForegroundColor Cyan;Write-Host "Acceso local: http://localhost:$port" -ForegroundColor Cyan }
function Install-App {
    Write-Title;if(-not (Test-Docker)){Write-Host 'Abre Docker Desktop y espera hasta que indique Engine running.' -ForegroundColor Red;return};if(-not (Get-Project)){return};Initialize-Env
    $current=Get-EnvValue APP_URL 'http://localhost';$url=Read-Host "URL pública [$current]";if($url){Set-EnvValue APP_URL $url}
    Write-Host 'Construyendo y arrancando GuardiaPro...' -ForegroundColor Cyan;Invoke-Compose up -d --build
    if($LASTEXITCODE -eq 0){Write-Host 'GuardiaPro instalado correctamente.' -ForegroundColor Green;Show-Url}else{Write-Host 'La instalación falló. Revisa los registros.' -ForegroundColor Red;Invoke-Compose logs --tail=100}
}
function Service-Menu { while($true){Write-Title;Write-Host 'ESTADO Y SERVICIOS' -ForegroundColor Cyan;Write-Option 1 'Ver estado';Write-Option 2 'Iniciar';Write-Option 3 'Detener';Write-Option 4 'Reiniciar';Write-Option 5 'Ver registros';Write-Option 6 'Volver';switch(Read-Host 'Opción'){'1'{Invoke-Compose ps;Pause-Menu}'2'{Invoke-Compose up -d;Pause-Menu}'3'{Invoke-Compose stop;Pause-Menu}'4'{Invoke-Compose restart;Pause-Menu}'5'{Invoke-Compose logs --tail=150;Pause-Menu}'6'{return}}} }
function Change-Port { Write-Title;Initialize-Env;$current=Get-EnvValue HTTP_PORT '80';$port=Read-Host "Nuevo puerto [$current]";if($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535){Write-Host 'Puerto inválido.' -ForegroundColor Red;return};Set-EnvValue HTTP_PORT $port;Invoke-Compose up -d --force-recreate frontend;Show-Url }
function User-Menu { while($true){Write-Title;Write-Host 'GESTIÓN DE USUARIOS' -ForegroundColor Cyan;Write-Option 1 'Listar usuarios';Write-Option 2 'Restablecer contraseña';Write-Option 3 'Volver';switch(Read-Host 'Opción'){'1'{Invoke-Compose exec -T backend node dist/src/admin-cli.js list-users;Pause-Menu}'2'{$email=Read-Host 'Email';$secure=Read-Host 'Nueva contraseña' -AsSecureString;$ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure);try{$password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)};if($password.Length -lt 8){Write-Host 'Debe tener al menos 8 caracteres.' -ForegroundColor Red}else{Invoke-Compose exec -T backend node dist/src/admin-cli.js reset-password $email $password};Pause-Menu}'3'{return}}} }
function Uninstall-App { Write-Title;Write-Option 1 'Quitar contenedores conservando datos';Write-Option 2 'Quitar contenedores y ELIMINAR base de datos';Write-Option 3 'Cancelar';switch(Read-Host 'Opción'){'1'{Invoke-Compose down --remove-orphans}'2'{if((Read-Host 'Escribe ELIMINAR para confirmar') -ceq 'ELIMINAR'){Invoke-Compose down -v --remove-orphans}}} }

while($true){Write-Title;Write-Host 'INSTALACIÓN' -ForegroundColor Cyan;Write-Option 1 'Instalar dependencias';Write-Option 2 'Instalar Control de Seguridad';Write-Host;Write-Host 'ADMINISTRACIÓN' -ForegroundColor Cyan;Write-Option 3 'Estado y control del servicio';Write-Option 4 'Cambiar puerto de Docker';Write-Option 5 'Ver URL y puerto';Write-Option 6 'Gestión de usuarios';Write-Host;Write-Host 'MANTENIMIENTO' -ForegroundColor Cyan;Write-Option 7 'Desinstalar';Write-Option 0 'Salir';switch(Read-Host 'Selecciona una opción'){'1'{Install-Dependencies;Pause-Menu}'2'{Install-App;Pause-Menu}'3'{Service-Menu}'4'{Change-Port;Pause-Menu}'5'{Write-Title;Show-Url;Pause-Menu}'6'{User-Menu}'7'{Uninstall-App;Pause-Menu}'0'{exit}}}

