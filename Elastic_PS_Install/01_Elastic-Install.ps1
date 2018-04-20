#Unzip library
Add-Type -AssemblyName System.IO.Compression.FileSystem 
function Unzip{
  	param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

$RunningService = Get-Service elastic*  | Where-Object { $_.Status -eq "Running" }
if ($RunningService){
	Write-Host "Stop running services : $($RunningService.Name) " -ForegroundColor Green
	Stop-Service $RunningService
	Sleep 2 #wait service stop to be able to remove fodler
}

$ExistingFolder = Get-Item D:\elasticsearch*
if ($ExistingFolder){
	Write-Host "Remove existing folders : $($ExistingFolder.Name)" -ForegroundColor Green
	Remove-Item $ExistingFolder -Force -Recurse
}

$UnzipFile = Get-Item "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\elasticsearch-5.5*.zip" | Sort-Object -Property LastWriteTime -Descending | Select-Object -first 1 
$UnzipFile = $UnzipFile.FullName
if (-not $UnzipFile){
  Write-Host  "No source zip found for ES?"  -ForegroundColor Red
  return
}
Write-Host "Unzipping $UnzipFile" -ForegroundColor Green
Unzip $UnzipFile "D:\"
Move-Item D:\elasticsearch-* D:\elasticsearch



Write-Host "Preparing Elastic Configuration" -ForegroundColor Green

#save copy of original conf files
Copy-Item D:\elasticsearch\config\elasticsearch.yml D:\elasticsearch\config\elasticsearch.yml_original
Copy-Item D:\ElasticSearch\config\jvm.options D:\ElasticSearch\config\jvm.options_original

New-Item -ItemType Directory D:\elasticsearch\data -ErrorAction Ignore | Out-Null
New-Item -ItemType Directory D:\elasticsearch\logs -ErrorAction Ignore | Out-Null

if($env:CLU_NAME -eq $null)
{
    Write-Host "What is the cluster name?"
    Write-Host ">" -NoNewLine
    $ClusterName = (Read-Host)
}
else{
    $ClusterName = $env:CLU_NAME
}

#Edit the following hosts names with other computer name of the future cluster group!
if($env:CLU_HOSTS -eq $null)
{
    Write-Host "What are the other nodes in the cluster (separate with commas)?"
    Write-Host ">" -NoNewLine
    $hostlist = (Read-Host)
    $hostlist += ",$env:ComputerName"
}
else
{
    $hostlist=$env:CLU_HOSTS
}

$hosts = $hostlist.Split(",") | Where-Object { $_.Length -gt 0 }
$hostlist = '"'+[String]::Join(":39300`", `"", $hosts)+":39300"""
$minimum_master_nodes = [Math]::Truncate($hosts.Count / 2 + 1)

$conf = Get-Content D:\elasticsearch\config\elasticsearch.yml_original
$conf = $conf.replace("#cluster.name: my-application", "cluster.name: $ClusterName")
$conf = $conf.replace("#node.name: node-1", "node.name: $ClusterName.$env:ComputerName")
$conf = $conf.replace("#Add custom attributes to the node:", "# Add custom attributes to the node:
node.master: true
node.data: true
")
$conf = $conf.replace("#path.data: /path/to/data", "path.data: D:\elasticsearch\data")
$conf = $conf.replace("#path.logs: /path/to/logs", "path.logs: D:\elasticsearch\logs
#Path repo
path.repo: \\$env:SQLBACKUP\SLOWSAN\Backup\elasticsearch\$ClusterName\")
$conf = $conf.replace("#bootstrap.memory_lock: true", "bootstrap.memory_lock: true")
$conf = $conf.replace("#network.host: 192.168.0.1", "network.host: 0.0.0.0")
$conf = $conf.replace("#http.port: 9200", "http.port: 39200
transport.tcp.port: 39300")
$conf = $conf.replace("#discovery.zen.ping.unicast.hosts: [`"host1`", `"host2`"]", "discovery.zen.ping.unicast.hosts: [$($hostlist)]")
$conf = $conf.replace("#discovery.zen.minimum_master_nodes: 3", "discovery.zen.minimum_master_nodes: $minimum_master_nodes")
$conf = $conf.replace("#action.destructive_requires_name: true", "action.destructive_requires_name: false")
$conf = $conf + "
#Added Conf:

#Avoid Log spam:
logger.deprecation.level: error
logger.org.elasticsearch.transport: error
"
$conf=$conf.Replace("`n", "`r`n") 
$conf | Set-Content  D:\elasticsearch\config\elasticsearch.yml 

#Creating Folder for snaps in backup folder
New-Item -ItemType Directory \\$env:SQLBACKUP\SLOWSAN\Backup\elasticsearch\$ClusterName\ -ErrorAction Ignore | Out-Null

cd D:\ #switch directory is important (in case of remote folder)

$CurrentService = Get-Service elasticsearch*
if($CurrentService ){
	Write-Host "Removing existing service"  -ForegroundColor Green
	. D:\elasticsearch\bin\elasticsearch-service.bat remove
}
Write-Host "Installing ES service" -ForegroundColor Green
. D:\elasticsearch\bin\elasticsearch-service.bat install

Write-Host "Setup automatic startup" -ForegroundColor Green
Set-Service elasticsearch-service-x64 -StartupType Automatic


$registryPath = "HKLM:\SOFTWARE\Wow6432Node\Apache Software Foundation\Procrun 2.0\elasticsearch-service-x64\Parameters\Java"
$ram = (Get-WmiObject Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum/1048576
if($ram -gt 6144) { $memES = $ram - 4096; } else { $memES = ($ram - 1024) / 2 }
New-ItemProperty -Path $registryPath -Name "JvmMs" -Value $memES -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "JvmMx" -Value $memES -PropertyType DWord -Force | Out-Null

Write-Host "Starting service Elastic (SYSTEM user)." -ForegroundColor Green

Get-Service elasticsearch* | Start-Service
Get-Service *elastic*
Write-Host "Checking Log (wait 15 secs)" -ForegroundColor Green
sleep 15
$StartLog = Get-Content D:\elasticsearch\logs\$($env:CLU_NAME).log
if (-not ($StartLog -like "*started*")){
	Write-Host "Not started correctly. Check Log Notepad D:\elasticsearch\logs\$($env:CLU_NAME).log" -ForegroundColor Red
}
Get-Service *elastic*

Write-host "Switching from SYSTEM to ElasticSearch service account"
#Change to run ES with dedicated account
Write-Host -NoNewline "Password for ElasticSearch account (Keepass Service Account) > " -ForegroundColor magenta
$pwd=(Read-Host)

#Update permisions on folder
$Acl = Get-Acl "D:\elasticsearch\"
$Ar1 = New-Object System.Security.AccessControl.FileSystemAccessRule("$env:USERDOMAIN\elasticsearch","Modify","ContainerInherit,ObjectInherit","None","Allow")
$Acl.AddAccessRule($Ar1)
Set-Acl "D:\elasticsearch\" $Acl
#Update service
$service = Get-WmiObject win32_service -filter "name='elasticsearch-service-x64'"
$service.change($null,$null,$null,$null,$null,$null,"$env:USERDOMAIN\ElasticSearch",$pwd) | Out-Null

Get-Service elasticsearch-* | Stop-service
Get-Service elasticsearch-* | Start-service

Write-Host "Elastic Install Done." -ForegroundColor Green
