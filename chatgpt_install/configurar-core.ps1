$HostAlias = "core"
$HostIp = "192.168.10.100"
$RemoteUser = "root"
$SshDir = Join-Path $env:USERPROFILE ".ssh"
$PrivateKey = Join-Path $SshDir "id_ed25519"
$ConfigFile = Join-Path $SshDir "config"

New-Item -ItemType Directory -Force $SshDir | Out-Null

if (-not (Test-Path $PrivateKey)) {
    ssh-keygen -t ed25519 -f $PrivateKey
}

@"
Host $HostAlias
  HostName $HostIp
  User $RemoteUser
  IdentityFile ~/.ssh/id_ed25519
"@ | Set-Content -Encoding ascii $ConfigFile

Get-Content "$PrivateKey.pub" |
    ssh "$RemoteUser@$HostIp" `
    "mkdir -p /root/.ssh; cat >> /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys"

ssh $HostAlias "echo Conexion SSH por clave lista"
