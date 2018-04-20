#Unzip library
Add-Type -AssemblyName System.IO.Compression.FileSystem 
function Unzip{
  	param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

cd D:/

$RunningService = Get-Service *kibana*  | Where-Object { $_.Status -eq "Running" }
if ($RunningService){
	Write-Host "Stop running services : $($RunningService.Name) " -ForegroundColor Green
	Stop-Service $RunningService
	Sleep 2 #wait service stop to be able to remove fodler
}

$ExistingFolder = Get-Item D:\kibana*
if ($ExistingFolder){
	Write-Host "Remove existing folders : $($ExistingFolder.Name)" -ForegroundColor Green
	Remove-Item $ExistingFolder -Force -Recurse
}


$UnzipFile = Get-Item "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\kibana-5.5*.zip" | Sort-Object -Property LastWriteTime -Descending | Select-Object -first 1 
$UnzipFile = $UnzipFile.FullName
if (-not $UnzipFile){
  Write-Host  "No source zip found for kibana?"  -ForegroundColor Red
  return
}
Write-Host "Unzipping $UnzipFile" -ForegroundColor Green
Unzip $UnzipFile "D:\"
Move-Item D:\kibana-* D:\kibana


Write-Host "Preparing Kibana Configuration" -ForegroundColor Green

#save copy of original conf files

Copy-Item D:\kibana\config\kibana.yml D:\kibana\config\kibana.yml_original

((Get-Content D:\kibana\config\kibana.yml_original)+"
server.host: 0.0.0.0
server.port: 35601
elasticsearch.url: ""http://localhost:39200""
kibana.index: "".kibana.dba""
logging.dest: D:\kibana\logs\Kibana.log
logging.quiet: true
"
).Replace("`n", "`r`n") | Set-Content D:\kibana\config\kibana.yml

New-Item -ItemType Directory -Path D:\kibana\logs | Out-Null

#Config Done

#install nssm to help install kibana as a service
Write-Host "Installing nssm to help install Kibana service" -ForegroundColor Green
$ExistingFolder = Get-Item D:\nssm*
if ($ExistingFolder){
	Write-Host "Remove existing folders : $($ExistingFolder.Name)" -ForegroundColor Green
	Remove-Item $ExistingFolder -Force -Recurse
}

$UnzipFile = Get-Item "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\nssm*.zip" | Sort-Object -Property LastWriteTime -Descending | Select-Object -first 1 
if (-not $UnzipFile){
  Write-Host  "No source zip found for nssm?"  -ForegroundColor Red
  return
}
Write-Host "Unzipping NSSM $UnzipFile" -ForegroundColor Green
Unzip $UnzipFile "D:\"
Move-Item D:\nssm* D:\nssm

#Install service
$CurrentService = Get-Service elastic-kibana
if($CurrentService ){
	$CurrentService |Stop-service
	Write-Host "Removing existing service"  -ForegroundColor Green
	. D:\nssm\win64\nssm.exe remove elastic-kibana
}
Write-Host "Installing Kibana service" -ForegroundColor Green

. D:\nssm\win64\nssm.exe install elastic-kibana D:\kibana\bin\kibana.bat
#The following could probably be done with nssm commands. Instead of registry
$registryPath = "HKLM:\System\CurrentControlSet\Services\elastic-kibana"
New-ItemProperty -Path $registryPath -Name "DisplayName" -Value "Elasticsearch Kibana" -PropertyType String -Force | Out-Null
$registryPath = "HKLM:\System\CurrentControlSet\Services\elastic-kibana\Parameters"
New-ItemProperty -Path $registryPath -Name "AppStderr" -Value "D:\kibana\logs\service.log" -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "AppStdout" -Value "D:\kibana\logs\service.log" -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "AppRotateFiles" -Value 1 -PropertyType DWord -Force | Out-Null


Write-Host -NoNewline "Start Kibana service? (y/n)" -ForegroundColor magenta
$answer = (Read-Host) 
if ($answer -contains "y"){
	Get-Service elastic-kibana | Start-Service
	#Need to wait a long time to get the started log
	sleep 6
	$StartLog = Get-Content D:\kibana\logs\Kibana.log
	if (-not ($StartLog -like "*Server running*")){
		Write-Host "Not started correctly. Check Log D:\kibana\logs\Kibana.log" -ForegroundColor Red
	}
}
Get-Service *elastic*
Write-Host "Kibana Install Done." -ForegroundColor Green
