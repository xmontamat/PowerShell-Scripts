#This script finds all stopped redis services and tries to start them.
#It will also send redis-cli commands to master services to check if they are Master or Slave
#If they are slave, sends a CLUSTER FAILOVER command to get back a master role. (this is to prevent having 2 master services on 1 server)

#Runs Every Minute by Scheduled Task 'Redis Maintenance'
#This is very important to switch back masters to their expected roles and avoid having two masters on one server (risk of cluster failure)


for ($i=0; $i -lt 6; $i++){
    #Auto service restart Deactivated on DEV & STAGE for test purposes
    IF (-not($env:COMPUTERNAME -like 'STGP*')){
        $StoppedServices =  Get-Service redis_* | Where-Object{$_.status -eq 'Stopped'} 
    }
    $Logfile = "D:\RedisMaintenanceAuto\MaintenanceLog.log"

	$CurrDateTime = Get-Date -UFormat %y-%m-%d.%H:%M:%S
    #Try Restarting stopped redis services
    if($StoppedServices)
    { 
        Start-service $StoppedServices
        foreach($service in $StoppedServices){
            Add-Content $Logfile -value "$CurrDateTime Service $($service.name) found stopped. Starting." 
        }
        sleep 2
    }

    #Get started services
    $StartedServices =  Get-Service redis_* | Where-Object{$_.status -eq 'Running'} 


    #Check for its supposed master service (from name) that the node is actually master from 
    #services.name exemple : redis_dev_cache_master_shard1_55000
    Foreach ($service in $StartedServices){
        $ServiceAttributes = $service.name.split('_')
        $ServiceEnv = $ServiceAttributes[1]
        $ServiceMasterSlave = $ServiceAttributes[3]
        $ServicePort = $ServiceAttributes[5]

        if ($ServiceMasterSlave -eq 'master')
        {
            $ExePath =" D:/Redis_$($ServiceEnv)/redis-cli.exe"
            $clu_nodes_details= ''
            $j = Start-Job -ScriptBlock {& $args[0] -c -p $args[1] cluster nodes} -ArgumentList @($ExePath, $ServicePort)
            if (Wait-Job $j -Timeout 3) { $clu_nodes_details = Receive-Job $j }
            Remove-Job -force $j

            foreach ($node_details in $clu_nodes_details.split('\n')){
                if ($node_details -like "*myself,slave*") #should be master ! let's failover
                {
                    $a = Get-Date
                    Write-host "Needed failover detected. Getting master role back from temp Master" -ForegroundColor Yellow
                    Add-Content $Logfile -value "$CurrDateTime $($service.Name): Needed failover detected. Getting master role back." 
                
                    $response
                    $j = Start-Job -ScriptBlock {& $args[0] -c -p $args[1] CLUSTER FAILOVER FORCE} -ArgumentList @($ExePath, $ServicePort)
                    #Note that force is not usefull here unless the slave node is not responding
                    if (Wait-Job $j -Timeout 3) { $response = Receive-Job $j }
                    Remove-Job -force $j
                    break;
                }
            }
        }
    }
	
	$DateStringDay = Get-Date -Format FileDate

    #Clean Redis log which are quickly flooded by messages 'clusterWriteDone' and 'WSA_IO_PENDING'
    Foreach ($service in $StartedServices){
        $ServiceAttributes = $service.name.split('_')
        $ServiceEnv = $ServiceAttributes[1]
        $ServiceRedisType = $ServiceAttributes[2]
        $ServiceMasterSlave = $ServiceAttributes[3]

        $LogPath = "D:/Redis_$($ServiceEnv)/Logs/$($ServiceRedisType)_$($ServiceMasterSlave)_RAWLog.txt"
        $CleanLogPath =  $LogPath.Replace('RAWLog', 'CleanLog').replace('Logs/' , "Logs/$($DateStringDay)_")
        $LogPath
        Get-Content $LogPath  | select-string -pattern 'clusterWriteDone' -notmatch | select-string -pattern 'WSA_IO_PENDING' -notmatch | Add-Content $CleanLogPath
        #clear flooded Log
        Set-Content $LogPath ""

    }
    sleep 8 # To be repeated 6 times every 8 seconds , so that it takes a bit less than 1 minute
	
    }