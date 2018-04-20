If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "Please run this as Administrator!"
    Exit
}

$InstallDir = 'D:\RedisMaintenanceAuto'
$DestinationFile = "$InstallDir\RedisMaintenanceTaskAuto.ps1"

$ExistingFolder = Get-Item D:\RedisMaintenanceAuto -ErrorAction Ignore
if ($ExistingFolder){
	Write-Host "Remove existing folders : $($ExistingFolder.Name)" -ForegroundColor Green
	Remove-Item $ExistingFolder -Force -Recurse
}
mkdir $InstallDir > $null
Copy-Item \\$env:SQLBACKUP\SLOWSAN\Scripts\Redis\RedisMaintenanceTaskAuto.ps1 $DestinationFile 

Write-Host "Copied PS maintance script to : $($DestinationFile)" -ForegroundColor Green

$TaskName = "Redis Maintenance"

$existingTask = Get-ScheduledTask | Where-Object{$_.Taskname -eq $TaskName}
if ($existingTask) {
    Write-Host "Removing previous ScheduledTask" -ForegroundColor Green
    Unregister-ScheduledTask -TaskName $TaskName  -Confirm:$false
}

Write-Host "Installing ScheduledTask" -ForegroundColor Green

$actions = 
    (New-ScheduledTaskAction -Execute PowerShell.exe -Argument $DestinationFile)
$trigger = New-ScheduledTaskTrigger -Daily -At 12am


$settings = New-ScheduledTaskSettingsSet -MultipleInstances Parallel
$principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount  -RunLevel Highest
$descr = "This task is in charge of Redis maintenance" 
$task = Register-ScheduledTask -TaskName $TaskName -Description $descr -Action $actions -Trigger $trigger -principal $principal

$task.Triggers.Repetition.Duration = "P1D" #Repeat for a duration of one day
$task.Triggers.Repetition.Interval = "PT1M" #Repeat every 1 min

$task | Set-ScheduledTask > $null

Write-Host "Done. Starting Task" -ForegroundColor Green

Start-ScheduledTask -TaskName $TaskName



