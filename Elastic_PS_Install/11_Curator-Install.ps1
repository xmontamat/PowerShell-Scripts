Add-Type -AssemblyName System.IO.Compression.FileSystem 
function Unzip{
  	param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

cd D:/

$InstallPath = "D:\curator"

$ExistingFolder = Get-Item $InstallPath -ErrorAction 'SilentlyContinue'
if ($ExistingFolder){
	Write-Host "Remove existing folders : $($ExistingFolder.Name)" -ForegroundColor Green
	Remove-Item $ExistingFolder -Force -Recurse
}

$UnzipFile = Get-Item "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\elasticsearch-curator-*.zip" | Sort-Object -Property LastWriteTime -Descending | Select-Object -first 1 
$UnzipFile = $UnzipFile.FullName
if (-not $UnzipFile){
  Write-Host  "No source zip found for curator?"  -ForegroundColor Red
  return
}
Write-Host "Unzipping $UnzipFile" -ForegroundColor Green
Unzip $UnzipFile "D:\"
Move-Item D:\curator-* $InstallPath 


Write-Host "Copy curator conf & action files" -ForegroundColor Green
Copy-Item "\\$env:SQLBACKUP\SLOWSAN\Scripts\ElasticSearch\Curator_MaintenanceConf\curator.yml" $InstallPath 
Copy-Item "\\$env:SQLBACKUP\SLOWSAN\Scripts\ElasticSearch\Curator_MaintenanceConf\ElasticMaintanceTaskAuto.ps1" $InstallPath 
mkdir $InstallPath\actions
Copy-Item "\\$env:SQLBACKUP\SLOWSAN\Scripts\ElasticSearch\Curator_MaintenanceConf\*.yml" $InstallPath\actions
mkdir $InstallPath\logs
$Ok = ""
Do {
$Answers = @("Y", "N", "EXIT")
Write-Host ""
Write-Host "Do you want to reinstall the Maintenance Task on Windows? " -ForegroundColor Yellow
Write-Host ""
Write-Host -NoNewline "Y/N > "
$InputResponse= (Read-Host).ToUpper()
$Ok = $Answers -contains $InputResponse
} Until ($Ok)

If ($InputResponse -eq 'Y'){
    Write-Host "Install Daily Maintenance ScheduledTask" -ForegroundColor Green
    $ComputerName = $env:ComputerName;
    Write-Host -NoNewline "Password for ElasticSearch account > "
    $pwd = (Read-Host)
    $SuggestedHostNumber = $env:ComputerName.SubString($env:ComputerName.IndexOf("0") + 1, 1)
    $SuggestedDailyStartTime = $SuggestedHostNumber+"am"
    $SuggestedHourlyStartTime = '1:'+$SuggestedHostNumber+"0 am"

    #First Task - Daily

    $existingTask = Get-ScheduledTask | Where-Object{$_.Taskname -eq "ElasticSearch Maintenance"}
    if ($existingTask) {
        Write-Host "Removing previous task" -ForegroundColor Green
        Unregister-ScheduledTask -TaskName "ElasticSearch Maintenance"  -Confirm:$false
    }

    $actions = 
        (New-ScheduledTaskAction -Execute "powershell" -Argument "$($InstallPath)\ElasticMaintanceTaskAuto.ps1" )
    $trigger = New-ScheduledTaskTrigger -Daily -At $SuggestedDailyStartTime
    $descr= "This daily task is in charge of ElasticSearch Indices maintenance task"
    Register-ScheduledTask -TaskName "ElasticSearch Maintenance" -Description "$descr" -User "$env:USERDOMAIN\ElasticSearch" -Password $pwd -Action $actions -Trigger $trigger
}
Write-Host "Done." -ForegroundColor Green
Do {
$Answers = @("Y", "N", "EXIT")
Write-Host ""
Write-Host "Do you want to run this task now? " -ForegroundColor Yellow
Write-Host ""
Write-Host -NoNewline "Y/N > "
$InputResponse= (Read-Host).ToUpper()
$Ok = $Answers -contains $InputResponse
} Until ($Ok)
If ($InputResponse -eq 'Y'){
    Write-Host "Running task" -ForegroundColor Green
    Start-ScheduledTask "ElasticSearch Maintenance" 
}

# Start task for tests : Get-ScheduledTask | Where-Object{$_.TaskName -like '*elastic*'} | Start-ScheduledTask
#D:\curator\curator --config D:\curator\curator.YML --dry-run curatorActiontests.YML
