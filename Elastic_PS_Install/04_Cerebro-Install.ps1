#Unzip library
Add-Type -AssemblyName System.IO.Compression.FileSystem 
function Unzip{
  	param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

cd D:/

$RunningService = Get-Service *cerebro*  | Where-Object { $_.Status -eq "Running" }
if ($RunningService){
	Write-Host "Stop running services : $($RunningService.Name) " -ForegroundColor Green
	Stop-Service $RunningService
	Sleep 2 #wait service stop to be able to remove fodler
}

$ExistingFolder = Get-Item D:\cerebro*
if ($ExistingFolder){
	Write-Host "Remove existing folders : $($ExistingFolder.Name)" -ForegroundColor Green
	Remove-Item $ExistingFolder -Force -Recurse
}


$UnzipFile = Get-Item "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\cerebro-*.zip" | Sort-Object -Property LastWriteTime -Descending | Select-Object -first 1 
$UnzipFile = $UnzipFile.FullName
if (-not $UnzipFile){
  Write-Host  "No source zip found for cerebro?"  -ForegroundColor Red
  return
}
Write-Host "Unzipping $UnzipFile" -ForegroundColor Green
Unzip $UnzipFile "D:\"
Move-Item D:\cerebro-* D:\cerebro


Write-Host "Preparing Cerebro Configuration" -ForegroundColor Green

#save copy of original conf files

Copy-Item D:\cerebro\conf\application.conf D:\cerebro\conf\application.conf_original

$clu_name = $($env:CLU_NAME)
if (-Not($clu_name)){
	$clu_name  = 'Local-CLU'
}

$conf = (Get-Content D:\cerebro\conf\application.conf_original)
$conf =$conf.Replace('secret =', 'secret = "63dea834ef054f5357528a688826d866b2faf660ad4d98f32e729608c7736295"
#oldsecret =')
#maybe change this to local?
$conf =$conf.Replace("hosts = ["
,
"hosts = [
  {
    host = ""http://localhost:39200""
    name = ""$clu_name""
  }")
$conf+="
"
$conf.Replace("`n", "`r`n") | Set-Content D:\cerebro\conf\application.conf

#Config Done

$ExistingFolder = Get-Item D:\nssm
if (-Not($ExistingFolder)){
#install nssm if not already installed via kibana (02)
	Write-Host "Installing nssm to help install Kibana service" -ForegroundColor Green

	$UnzipFile = Get-Item "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\nssm*.zip" | Sort-Object -Property LastWriteTime -Descending | Select-Object -first 1 
	if (-not $UnzipFile){
	  Write-Host  "No source zip found for nssm?"  -ForegroundColor Red
	  return
	}
	Write-Host "Unzipping NSSM $UnzipFile" -ForegroundColor Green
	Unzip $UnzipFile "D:\"
	Move-Item D:\nssm* D:\nssm
}

#Remove service if exists
$CurrentService = Get-Service elastic-cerebro*
if($CurrentService ){
	$CurrentService |Stop-service
	Write-Host "Removing existing service"  -ForegroundColor Green
	. D:\nssm\win64\nssm.exe remove elastic-cerebro
}
#Install service
Write-Host "Installing Cerebro service" -ForegroundColor Green
. D:\nssm\win64\nssm.exe install elastic-cerebro D:/cerebro/bin/cerebro.bat
. D:\nssm\win64\nssm.exe set elastic-cerebro appparameters "-Dhttp.port=39000"
. D:\nssm\win64\nssm.exe set elastic-cerebro DisplayName "Elasticsearch Cerebro"

Start-Service elastic-cerebro
Get-Service elastic-cerebro
Write-Host "Cerebro Install Done." -ForegroundColor Green
