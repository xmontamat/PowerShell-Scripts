Add-Type -AssemblyName System.IO.Compression.FileSystem 
function Unzip{
  	param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

cd D:/

$ExistingFolder = Get-Item D:\Templates*
if ($ExistingFolder){
	Write-Host "Remove existing folders : $($ExistingFolder.Name)" -ForegroundColor Green
	Remove-Item $ExistingFolder -Force -Recurse
}

Copy-Item \\$env:SQLBACKUP\SLOWSAN\Scripts\ElasticSearch\Templates D: -Force -Recurse
Get-ChildItem D:\Templates\*.json | Foreach {
    $TemplateName = $PSItem.Name.Replace(".json", "");
    $DisplayName = $TemplateName.Replace("_", " ");
	$Content = Get-content $PSItem.FullName
	if  ($result){	Remove-Variable result }
    $result = Invoke-RestMethod "http://$($env:ComputerName):39200/_template/$TemplateName" -Method Post -Body $Content
    if ($result.acknowledged) {
	    Write-Host "$DisplayName installed" -ForegroundColor Green
    }
    Else {
	    Write-Host "$DisplayName installation failed" -ForegroundColor Red
    }
}


if  ($result){	Remove-Variable result }
$result  = Invoke-RestMethod http://localhost:39200/_snapshot/backup_repository -Method Post -Body '{ "type":"fs", "settings":{ "compress":"true", "location":"AutomaticSnapshots" } }'
if ($result.acknowledged) {
	Write-Host "Backup repository configured" -ForegroundColor Green
}
Else {
	Write-Host "Backup repository configuration failed" -ForegroundColor Red
}

# rmdir D:\ElasticSearchMaintenance -Recurse -Force -ErrorAction Ignore
# Unzip "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\ElasticSearchMaintenance.zip" "D:\"

# $ComputerName = $env:ComputerName;
# $Prefix = $ComputerName.Substring(0, $ComputerName.IndexOf("-"))
# if(Test-Path D:\ElasticSearchMaintenance\Config\App.config.$Prefix) {
    # Move-Item -Path D:\ElasticSearchMaintenance\Config\App.config.$Prefix -Destination D:\ElasticSearchMaintenance\ElasticSearchMaintenance.exe.config -Force
	# Write-Host "Maintenance job configuration: $Prefix" -ForegroundColor Green
# }
# Else {
	# Write-Host "Cannot find maintenance job configuration ($Prefix)" -ForegroundColor Red
# }

# Write-Host -NoNewline "Password for ElasticSearch account > "
# $pwd = (Read-Host)
# $SuggestedHostNumber = $env:ComputerName.SubString($env:ComputerName.IndexOf("0") + 1, 1)
# $SuggestedDailyStartTime = $SuggestedHostNumber+"am"
# $SuggestedHourlyStartTime = '1:'+$SuggestedHostNumber+"0 am"

## First Task - Daily
# $action = New-ScheduledTaskAction -Execute "D:\ElasticSearchMaintenance\ElasticSearchMaintenance.exe" –Argument "-d"
# $trigger = New-ScheduledTaskTrigger -Daily -At $SuggestedDailyStartTime
# Register-ScheduledTask -TaskName "ElasticSearch Maintenance" -Description "This daily task is in charge of ElasticSearch Indices maintenance task" -User "$env:USERDOMAIN\ElasticSearch" -Password $pwd -Action $action -Trigger $trigger

##Second Task - Hourly
# $action = New-ScheduledTaskAction -Execute "D:\ElasticSearchMaintenance\ElasticSearchMaintenance.exe" –Argument "-h"
# $trigger =  New-ScheduledTaskTrigger -Daily -At $SuggestedHourlyStartTime
# $task = Register-ScheduledTask -TaskName "ElasticSearch Hourly Maintenance" -Description "This hourly task is in charge of ElasticSearch Indices maintenance task" -User "$env:USERDOMAIN\ElasticSearch" -Password $pwd -Action $action -Trigger $trigger
# $task.Triggers.Repetition.Duration = "P1D"
# $task.Triggers.Repetition.Interval = "PT1H"
# $task | Set-ScheduledTask -User "$env:USERDOMAIN\ElasticSearch" -Password $pwd
