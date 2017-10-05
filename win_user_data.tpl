<powershell>

$timestamp = Get-Date -Format o | foreach {$_ -replace ":", "."}
echo "$timestamp : *** UserData Started ***"  > ~/userdata.log

echo "parameters:"  >> ~/userdata.log
echo "  p_hostname: ${p_hostname}" >> ~/userdata.log
echo "  p_domainname: ${p_domainname}" >> ~/userdata.log
#echo "  p_adminpwd: ${p_adminpwd}" >> ~/userdata.log
#echo "  p_sshkey: ${p_sshkey}" >> ~/userdata.log
echo "  p_dockerwinurl: ${p_dockerwinurl}" >> ~/userdata.log

$newhostname = "${p_hostname}"
$newdomainname = "${p_domainname}"
$adminpwd = "${p_adminpwd}"
$pubkey = "${p_sshkey}"
$dockerwinurl = "${p_dockerwinurl}"


# Set the local admin password
#
$temphostname = (Get-WMIObject Win32_ComputerSystem | Select-Object -ExpandProperty name)
$localadminstr = ("WinNT://" + $temphostname + "/Administrator")
([ADSI] "$localadminstr").SetPassword("$adminpwd")


# set hostname
#
Rename-Computer -NewName "$newhostname"
$computerName = $env:computername                                                                                               
$DNSSuffix = "$newdomainname"                                                                                               
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\" -Name Domain -Value $DNSSuffix                     
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\" -Name "NV Domain" -Value $DNSSuffix                
Set-DnsClientGlobalSetting -SuffixSearchList $DNSSuffix 

#echo "ssh key - 1.."  >> ~/userdata.log
# Generate ssh authorized keys file and add pubkey (finish off after openssh installed)
#
Write-Host "Adding public key from instance metadata to authorized_keys"
New-Item -Type Directory ~\.ssh > $null
$keyPath = "~\.ssh\authorized_keys1"
$pubkey | Out-File $keyPath
# unix2dos needed?
#get-content ~\.ssh\authorized_keys1 |% {$_.replace("`n", "`r`n")} | out-file -filename ~/.ssh/authorized_keys


# powershell settings
#
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'


# turn off anti-virus
#
Write-Host "Disabling anti-virus monitoring"
Set-MpPreference -DisableRealtimeMonitoring $true


echo "sshd - install.."  >> ~/userdata.log
# Install OpenSSH server and configure
#
Write-Host "Downloading OpenSSH"
Invoke-WebRequest "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v0.0.19.0/OpenSSH-Win64.zip" -OutFile OpenSSH-Win64.zip -UseBasicParsing

Write-Host "Expanding OpenSSH"
Expand-Archive OpenSSH-Win64.zip C:\
Remove-Item -Force OpenSSH-Win64.zip

Write-Host "Disabling password authentication"
#Add-Content C:\OpenSSH-Win64\sshd_config "`nPasswordAuthentication no"
Add-Content C:\OpenSSH-Win64\sshd_config "`nUseDNS no"
Add-Content C:\OpenSSH-Win64\sshd_config "PermitRootLogin yes"
Add-Content C:\OpenSSH-Win64\sshd_config "PubkeyAuthentication yes"
Add-Content C:\OpenSSH-Win64\sshd_config "LogLevel DEBUG3"

Push-Location C:\OpenSSH-Win64

Write-Host "Installing OpenSSH"
& .\install-sshd.ps1

Write-Host "Generating host keys"
.\ssh-keygen.exe -A

Write-Host "Fixing Host File Permissions"
.\FixHostFilePermissions.ps1 -Confirm:$false

Write-Host "Fixing User File Permissions"
.\FixUserFilePermissions.ps1

Pop-Location

echo "path - sshd.."  >> ~/userdata.log
# add sshd directory to path
$newPath = 'C:\OpenSSH-Win64;' + [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)


#echo "ssh key - 2.."  >> ~/userdata.log
# finish setup of openssh authorized keys for administrator account
#
Push-Location ~\.ssh

# use a key generated by windows ssh-keygen to get file format right! (ref: line 1 exceeds valid length)
C:\OpenSSH-Win64\ssh-keygen.exe -t rsa -f tempkey -N docker
cp .\tempkey.pub ~\.ssh\authorized_keys
Get-Content ~\.ssh\authorized_keys1 | Add-Content ~\.ssh\authorized_keys
rm .\tempkey*
rm ~\.ssh\authorized_keys1

# set file ACLs so sshd system service can read it
icacls ~\.ssh\authorized_keys /inheritance:d
icacls ~\.ssh\authorized_keys /remove `"NT AUTHORITY\SYSTEM`"
icacls ~\.ssh\authorized_keys /remove `"NT SERVICE\sshd`"
icacls ~\.ssh\authorized_keys /grant `"NT SERVICE\sshd`":`(R`)

Pop-Location


echo "sshd - firewall.."  >> ~/userdata.log
# Open up ssh port 22
Write-Host "Opening firewall port 22"
New-NetFirewallRule -Protocol TCP -LocalPort 22 -Direction Inbound -Action Allow -DisplayName SSH

# Configure sshd service (will start after reboot)
Write-Host "Setting sshd service startup type to 'Automatic'"
Set-Service sshd -StartupType Automatic
Write-Host "Setting sshd service restart behavior"
sc.exe failure sshd reset= 86400 actions= restart/500


echo "choco - install.."  >> ~/userdata.log
# Install Chocolatey package manager and some utilities
#
Invoke-WebRequest https://chocolatey.org/install.ps1 -UseBasicParsing | iex

echo "choco - path.."  >> ~/userdata.log
$newPath2 = 'C:\Program Files (x86)\vim\vim80;C:\Program Files\Git\bin' + [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("PATH", $newPath2, [EnvironmentVariableTarget]::Machine)

echo "choco - vim.."  >> ~/userdata.log
choco install vim -y
echo "choco - git.."  >> ~/userdata.log
choco install git -y
echo "choco - python.."  >> ~/userdata.log
choco install python -y


# Install NuGet Package Manager
echo "NuGet - install.."  >> ~\userdata.log
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force


$timestamp = Get-Date -Format o | foreach {$_ -replace ":", "."}
echo "$timestamp : *** Infra config complete:"  >> ~\userdata.log


Push-Location ~\

echo "docker-ee - download.."  >> ~\userdata.log
invoke-webrequest -UseBasicparsing -Outfile docker.zip $dockerwinurl

echo "docker-ee - processing zip.."  >> ~\userdata.log
Expand-Archive docker.zip -DestinationPath $Env:ProgramFiles
Remove-Item -Force docker.zip

# Install Docker. This will require rebooting.
echo "docker-ee - install.."  >> ~\userdata.log
$null = Install-WindowsFeature containers

echo "docker-ee - env.."  >> ~\userdata.log
$env:path += ";$env:ProgramFiles\docker"
$newPath = "$env:ProgramFiles\docker;" + [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)

echo "docker-ee service - define.."  >> ~\userdata.log
dockerd --register-service
Set-Service docker -StartupType Automatic

echo "docker-ee - firewall rules.."  >> ~/userdata.log
netsh advfirewall firewall add rule name="docker_80_in"    dir=in action=allow  protocol=TCP localport=80    | Out-Null;
netsh advfirewall firewall add rule name="docker_443_in"   dir=in action=allow  protocol=TCP localport=443   | Out-Null;
netsh advfirewall firewall add rule name="docker_8443_in"  dir=in action=allow  protocol=TCP localport=8443  | Out-Null;
netsh advfirewall firewall add rule name="docker_8080_in"  dir=in action=allow  protocol=TCP localport=8080  | Out-Null;
netsh advfirewall firewall add rule name="docker_4000_in"  dir=in action=allow  protocol=TCP localport=4000  | Out-Null;
netsh advfirewall firewall add rule name="docker_5000_in"  dir=in action=allow  protocol=TCP localport=5000  | Out-Null;
netsh advfirewall firewall add rule name="docker_2376_in"  dir=in action=allow  protocol=TCP localport=2376  | Out-Null;
netsh advfirewall firewall add rule name="docker_2377_in"  dir=in action=allow  protocol=TCP localport=2377  | Out-Null;
netsh advfirewall firewall add rule name="docker_4789_in"  dir=in action=allow  protocol=UDP localport=4789  | Out-Null;
netsh advfirewall firewall add rule name="docker_4789_in"  dir=in action=allow  protocol=TCP localport=4789  | Out-Null;
netsh advfirewall firewall add rule name="docker_4789_out" dir=out action=allow protocol=UDP localport=4789  | Out-Null;
netsh advfirewall firewall add rule name="docker_4789_out" dir=out action=allow protocol=TCP localport=4789  | Out-Null;
netsh advfirewall firewall add rule name="docker_7946_in"  dir=in action=allow  protocol=UDP localport=7946  | Out-Null;
netsh advfirewall firewall add rule name="docker_7946_in"  dir=in action=allow  protocol=TCP localport=7946  | Out-Null;
netsh advfirewall firewall add rule name="docker_7946_out" dir=out action=allow protocol=UDP localport=7946  | Out-Null;
netsh advfirewall firewall add rule name="docker_7946_out" dir=out action=allow protocol=TCP localport=7946  | Out-Null;
netsh advfirewall firewall add rule name="docker_12376_in" dir=in action=allow  protocol=TCP localport=12376 | Out-Null;
netsh advfirewall firewall add rule name="docker_12379_in" dir=in action=allow  protocol=TCP localport=12379 | Out-Null;
netsh advfirewall firewall add rule name="docker_12380_in" dir=in action=allow  protocol=TCP localport=12380 | Out-Null;
netsh advfirewall firewall add rule name="docker_12381_in" dir=in action=allow  protocol=TCP localport=12381 | Out-Null;
netsh advfirewall firewall add rule name="docker_12382_in" dir=in action=allow  protocol=TCP localport=12382 | Out-Null;
netsh advfirewall firewall add rule name="docker_12383_in" dir=in action=allow  protocol=TCP localport=12383 | Out-Null;
netsh advfirewall firewall add rule name="docker_12384_in" dir=in action=allow  protocol=TCP localport=12384 | Out-Null;
netsh advfirewall firewall add rule name="docker_12385_in" dir=in action=allow  protocol=TCP localport=12385 | Out-Null;
netsh advfirewall firewall add rule name="docker_12386_in" dir=in action=allow  protocol=TCP localport=12386 | Out-Null;
netsh advfirewall firewall add rule name="docker_12387_in" dir=in action=allow  protocol=TCP localport=12387 | Out-Null;

Pop-Location


# Fix authorized keys ACL, think Chocolatey install strips it above so repeat here
# ACL needs to stick post reboot: icacls ~\.ssh\authorized_keys /grant `"NT SERVICE\sshd`":`(R`)
echo "ssh key - ACLs:"  >> ~/userdata.log
C:\OpenSSH-Win64\FixHostFilePermissions.ps1 -Confirm:$false


$timestamp = Get-Date -Format o | foreach {$_ -replace ":", "."}
echo "$timestamp : *** UserData Ended ***"  >> ~/userdata.log


echo "docker-ee creating powershell script ~/configure-docker.ps1"  >> ~\userdata.log
"# Powershell to configure docker daemon
Restart-Service docker;

# Setting up Docker daemon to listen on port 2376 with TLS
if (!(Test-Path C:\ProgramData\docker\daemoncerts\key.pem)) {
    New-Item -ItemType directory -Path C:\ProgramData\docker\daemoncerts | Out-Null;
    docker run --rm -v C:\ProgramData\docker\daemoncerts:C:\certs docker/ucp-agent-win:2.2.2 generate-certs ;
}
Stop-Service docker;
dockerd --unregister-service;
dockerd -H npipe:// -H 0.0.0.0:2376 --tlsverify --tlscacert=C:\ProgramData\docker\daemoncerts\ca.pem --tlscert=C:\ProgramData\docker\daemoncerts\cert.pem --tlskey=C:\ProgramData\docker\daemoncerts\key.pem --register-service;
Start-Service docker;

# daemon setup script from container..
docker container run --rm docker/ucp-agent-win:2.2.2 windows-script | powershell -noprofile -noninteractive -command 'Invoke-Expression -Command $input'

# pull other cluster and test image
docker image pull docker/ucp-dsinfo-win:2.2.2
docker run microsoft/dotnet-samples:dotnetapp-nanoserver

" | out-file ~/configure-docker.ps1


$timestamp = Get-Date -Format o | foreach {$_ -replace ":", "."}
echo "$timestamp : *** Now rebooting ***" >> ~\userdata.log
Restart-Computer -Force

</powershell>