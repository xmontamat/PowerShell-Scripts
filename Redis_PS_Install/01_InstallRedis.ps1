#This Script will :
#    - Ask the user which type of redis server to install
#    - Get the redis source from the slowsan 
#    - Extract the source to D:/Redis
#    - Create a conf file for the redis type chosen
#    - Create a Windows service linked to that conf
#    - Start the windows service
#
#    Note that the conf of the REdis server specifies a cluster, which needs to be configured separatly to discover the other nodes etc.


############ PARAMS ###########

If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "Please run this as Administrator!"
    Exit
}
#Check if var are setup
IF($env:CLU_HOSTS -eq $null -or $env:CLU_NAME -eq $null){
	Write-Host "Env variables CLU_HOSTS or CLU_NAME not setup! Please run first script 00_SetEnvVariables.ps1. (Or reboot to apply) " -ForegroundColor Red
	Exit
}

cd D:/

$global:Account_Pass
$global:GlobalForceReinstall = 0


#Get other nodes details (from $env variable : clu_hosts)
$global:clu_hosts = $env:CLU_HOSTS.Split(',')

#Create table of types of redis for the user to chose from

$TypesOfRedis = New-Object system.Data.DataTable “Redis Servers types”
$columns = @()
$columns+= New-Object system.Data.DataColumn Env,([string])
$columns+= New-Object system.Data.DataColumn RedisType,([string]) #The type of project hosted on this redis
$columns+= New-Object system.Data.DataColumn Master_Slave,([string]) #The role of the service in the cluster
$columns+= New-Object system.Data.DataColumn Port,([int]) #Port automatically suggested
$columns+= New-Object system.Data.DataColumn MemoryNode,([string])
$columns+= New-Object system.Data.DataColumn ShardId,([string])
$columns+= New-Object system.Data.DataColumn ServiceName,([string])
foreach ($column in $columns){
    $TypesOfRedis.columns.add($column)
}

#Do not change order
if ($env:COMPUTERNAME -like "STGP*"){
    $Envs=@("Dev","ST1", "ST2")
}
else {
    Write-Host  "Env not recognized"  -ForegroundColor Red
    exit
}
#Do not change order
$Types =@("Cache", "Push", "Myope")

$Master_Slaves =@("Master", "Slave")

#The port for the first service (DEV Cache Master)
$SartingPort= [int]55000

foreach($Env in $Envs){
    foreach($Type in $Types){
        foreach($Master_Slave in $Master_Slaves)
        {
            $row = $TypesOfRedis.NewRow()
            $row.Env = $Env
            $row.RedisType = $Type
            $row.Master_Slave = $Master_Slave
            $row.MemoryNode = '1Gb'

            #Configure ShardId
            $lastTwoCharsOfComputerName = $env:ComputerName.Substring($env:ComputerName.Length - 2)
            $shardId = [int]$lastTwoCharsOfComputerName
            #Configure ShardId for a master (local nodeID)
            if($Master_Slave -eq 'Master'){
                $row.ShardId = 'Shard'+$shardId
            }
            #Configure ShardId for a slave (local nodeID + 1)
            elseif($Master_Slave -eq 'Slave'){
                if($shardId -lt  $clu_hosts.length){
                    $row.ShardId = 'Shard'+($shardId+1)
                }
                else{
                    $row.ShardId = 'Shard1'
                }
            }


            #Port convention : Use starting port 55000 and :
            #Add 10 per type
            #Add 100 per env 
            #Last digit 0 for master or 1 for slave
            $row.Port = $SartingPort+ 100*($Envs.IndexOf($Env)) +10*($Types.IndexOf($Type)) + 1*($Master_Slaves.IndexOf($Master_Slave))
            
            $row.ServiceName = 'Redis_'+$Env+'_'+$Type+'_'+$Master_Slave+'_'+$row.ShardId+'_'+$row.Port

            $TypesOfRedis.Rows.Add($row)
        }
    }
}

$userchoices = ($TypesOfRedis | out-gridview -Title "Chose your Redis install"  -passthru)
# skip function definitons to see next step (user choice done)

#Function to configure Conf File from serverType object and install related service
function ConfigureServer
{
    Param ([PSCustomObject]$serverObj, [string]$OriginalConfFilePath)
    $OriginalConfFilePath =  "D:\Redis_$($serverObj.env)\redis.windows-service.original_conf"
    if (-not(Get-Item $OriginalConfFilePath -ErrorAction 'SilentlyContinue')){
      Write-Host  "Missing original conf file"  -ForegroundColor Red
      exit
    }
    #Always start from the original conf
    $conf = Get-Content $OriginalConfFilePath
    $InstallDirectory = (Get-Item $OriginalConfFilePath).DirectoryName
    $portNum = [string]$serverObj.port
    #NodeName will be used to setup the install sub folders and conf file names
    $NodeName = $serverObj.RedisType+'_'+$serverObj.Master_Slave
    #Adding port to FullName to generate explicit service name 
    $ServiceName = $serverObj.ServiceName
    
    #Start cutomizing conf file

    #generic_conf
    $conf = $conf.replace('port 6379', "port $portNum") #note: this also changes commented line # cluster-announce-port 6379
    #$conf = $conf.replace('# bind 127.0.0.1', "bind "+$serverObj.BoundIP)
    $conf = $conf.replace('dir ./', "dir ./$nodeName/data")
    $conf = $conf.replace('# maxmemory <bytes>', 'maxmemory '+$serverObj.MemoryNode) 
    $conf = $conf.replace('loglevel notice', 'loglevel warning') #Important to avoid flood
    $conf = $conf.replace('syslog-enabled yes', 'syslog-enabled no')
    
    $conf = $conf.replace('logfile "Logs/redis_log.txt"', 'logfile "Logs/'+$nodeName+'_RAWlog.txt"')
    # $conf = $conf.replace('logfile "Logs/redis_log.txt"', 'logfile "'+$nodeName+'/Logs/redis_log.txt"') # This does not work for some reason, the service won't start
	

    #cluster_conf
    $conf = $conf.replace('# cluster-enabled yes', "cluster-enabled yes")
    $conf = $conf.replace('# cluster-config-file nodes-6379.conf', "cluster-config-file clu_state_$nodeName.conf")
    $conf = $conf.replace('# cluster-node-timeout 15000', "cluster-node-timeout 2000")
	

    #minimum data loss on crash
    $conf = $conf.replace('appendonly no', "appendonly yes")
    #$conf = $conf.replace('', "")

    $conf=$conf.Replace("`n", "`r`n") 

    #Check for existing folder, ask if force reinstall
    $ExistingFolder = Get-Item $InstallDirectory\$nodeName -ErrorAction 'SilentlyContinue'
    $ExistingService = Get-Service $serviceName -ErrorAction 'SilentlyContinue'
    If ($ExistingFolder -or $ExistingService)
    {
        $ForceReinstall = AskForceReinstall $InstallDirectory\$nodeName
        if ($ForceReinstall -eq 1)
        {
            if($ExistingFolder){
              Write-Host "Removing existing folder : $ExistingFolder" -ForegroundColor Green
                 Remove-Item $ExistingFolder -Force -Recurse -ErrorAction Stop #Could probably return an error if folder used by someone
            }
            if($ExistingService){
                Stop-service $ExistingService
                $service = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
                $service.delete() >$null
                Write-Host "Removing existing service : $serviceName" -ForegroundColor Green
            }
        }
        else  {
            Write-Host "Abort install of this service" -ForegroundColor Yellow
        }
    }

    $NewConfFile = "$InstallDirectory\$nodeName\$nodeName.conf"
    if (-not(GeT-Item "$InstallDirectory\$nodeName"  -ErrorAction 'SilentlyContinue')){
        mkdir "$InstallDirectory\$nodeName" >$null
        #Creating logs sub folder: (Removed , not used because redis couldn't start when changing the log to this folder)
        #mkdir "$InstallDirectory\$nodeName\Logs" >$null
        #Creating data sub folder:
        mkdir "$InstallDirectory\$nodeName\data" >$null
    }
    #Recreates Logs file if not exists otherwise the service won't start
    mkdir "$InstallDirectory\Logs" -ErrorAction SilentlyContinue >$null
    #Saves the custom conf file
    $conf | Set-Content $NewConfFile
    Write-Host "Saved custom conf file : $NewConfFile" -ForegroundColor 'Green'

    
    Write-Host "Creating associated service" -ForegroundColor 'Green'
    #Set and startup redis service
    cd $InstallDirectory
    ./redis-server.exe --service-install "$nodeName\$nodeName.conf" --service-name $serviceName --port $portNum
    
    Write-Host "Service created : $serviceName" -ForegroundColor 'Green'
    
    Write-Host "Trying to start the service with default account" -ForegroundColor 'Green'
    $InstallResult = ./redis-server.exe --service-start --service-name "$serviceName" --loglevel verbose
    $color = 'yellow'
    If ($InstallResult -like '*failed to start*') { $color = 'red'  }
    elseif ($InstallResult -like '*success*') { $color = 'Green'  }

    Write-host $InstallResult -ForegroundColor $color

    #SETUP real permissions
    $AccountName = 'Redis_service'
    Write-host "Switching service account from SystemDefault to $AccountName" -ForegroundColor 'Green'
    #Change to run ES with dedicated account
    
    #Testing account login
    while (-not ((new-object directoryservices.directoryentry "","$env:USERDOMAIN\$AccountName",$Account_Pass).psbase.name -ne $null)){
        Write-Host -NoNewline "Enter pass for $env:USERDOMAIN\$AccountName (not set or badly set) , see Keepass $AccountName " -ForegroundColor magenta
        $global:Account_Pass= Read-Host  "Password:"
    }

    #Update service to start with dedicated account
    $service = Get-WmiObject win32_service -filter "name='$serviceName'"
    $service.change($null,$null,$null,$null,$null,$null,"$env:USERDOMAIN\$AccountName",$Account_Pass) | Out-Null
    $service = Get-WmiObject win32_service -filter "name='$serviceName'"
    Write-host "Service account switched successfully to "$($service.StartName)  -ForegroundColor Green
    Write-host "Restarting service" -ForegroundColor Green
    
    Stop-service $serviceName -ErrorAction Ignore
    Sleep 0.5
    $start_result = ./redis-server.exe --service-start --service-name "$serviceName" --loglevel verbose 
    if($start_result -like '*Redis service successfully started*')
    { $color = 'Green'}
    else{  $color = 'red'  }
    write-host $start_result -ForegroundColor $color

}
#function to delete all existing redis services :
Function DeleteAllRedisServices ($env){
    $existingservices = get-service redis_$env*

    foreach($service in $existingservices){
        Stop-service $service
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='$($service.name)'"
        $service.delete() >$null
        Write-host $service.name removed -ForegroundColor Green
    }
    sleep 1
}

#Checks if the port is opened
Function CheckConnection ($Hostname, $portToCheck){
    Write-Host "Checking connection to $Hostname : $portToCheck" -ForeGroundColor Green
    If ( Test-Connection $Hostname -Count 1 -Quiet) {
        try {       
            $null = New-Object System.Net.Sockets.TCPClient -ArgumentList $Hostname,$portToCheck
            Write-host "$Hostname : Port $portToCheck Opened" -ForeGroundColor Green
        }
        catch {
                Write-host "$Hostname : Port $portToCheck Closed" -ForeGroundColor Red
        }
    }
    Else {
        Write-host "$Hostname Did not respond to ping." -ForeGroundColor Red
    }
}

#Make sure the user want to delete a folder
Function AskForceReinstall ($FolderPath){
    Write-Host "An install already exists on this folder : $FolderPath" -ForegroundColor Magenta
    Write-Host "Do you want to stop all associated services and delete the folder to reinstall from scratch? " -ForegroundColor Magenta
    $res = (read-host "Y/N/A(yes all)").ToUpper() 
    if ($res -eq "Y"){
        return 1
    }
    if ($res -eq "N"){
        return 0
    }
    if ($res -eq "A"){
        $GlobalForceReinstall = 1
        return 1
    }
    else{
        return 0
    }
}


##USER CHOICE DONE
if ($userchoices) {
    #For each env in the choices, Create install folder if not existing
    foreach ($env in ($userchoices.Env | select -uniq))
    {
        
        #Install Redis from source zip on slowsan
        #Copy zip source if reinstall force or no install found 
        $DestinationPath = "D:\Redis_$env"
        $SourcePath = "\\$env:SQLBACKUP\SLOWSAN\Sources\Redis\Redis-x64-3.0.504.zip"
    
        #If folder exists
        $ExistingFolder = Get-Item $DestinationPath  -ErrorAction 'SilentlyContinue'
        $ForceReinstall = $GlobalForceReinstall
        #If the folder fot this env already exists, ask if reinstall wanted
        if  ($ExistingFolder -and $ForceReinstall -eq 0){
            $ForceReinstall = AskForceReinstall ($ExistingFolder)
        }
        if ($ExistingFolder -and ($ForceReinstall -eq 1)){
            #Custom function for easy dev, Deletes ALL redis services for this env
            DeleteAllRedisServices $env
        }
        else {
            Write-host "Skipping Env folder uninstall"  -ForegroundColor Green
        }

        #CREATE Env folder And unzip source 
        if(-not ( $ExistingFolder ) -or $ForceReinstall -eq 1)
        {
            if( $ExistingFolder -and $ForceReinstall -eq 1)
            {
	             Write-Host "Removing existing folders : $ExistingFolder" -ForegroundColor Green
                 Remove-Item $ExistingFolder -Force -Recurse -ErrorAction Stop #Could probably return an error if folder used by someone
            }

            #Unzip lib
            Add-Type -AssemblyName System.IO.Compression.FileSystem 
            $UnzipFile = (Get-Item $SourcePath -ErrorAction 'SilentlyContinue').FullName
            if (-not $UnzipFile){
              Write-Host  "No source zip found for $SourcePath ?"  -ForegroundColor Red
              return
            }
            Write-Host "Unzipping $UnzipFile" -ForegroundColor Green
            [System.IO.Compression.ZipFile]::ExtractToDirectory($UnzipFile, $DestinationPath)
            #Duplicate original conf
            Copy-Item "$DestinationPath\redis.windows-service.conf" "$DestinationPath\redis.windows-service.original_conf"
            Write-Host "Unzip done to $DestinationPath" -ForegroundColor Green

            #Update permisions on folder
            $AccountName = 'Redis_service'
            Write-host "Updating folder permissions for account : $AccountName" -ForegroundColor Green
            $Acl = Get-Acl $DestinationPath
            $Ar1 = New-Object System.Security.AccessControl.FileSystemAccessRule("$env:USERDOMAIN\$AccountName","Modify","ContainerInherit,ObjectInherit","None","Allow")
            $Ar2 = New-Object System.Security.AccessControl.FileSystemAccessRule("$env:USERDOMAIN\grp_admin_servers_dba","FullControl","ContainerInherit,ObjectInherit","None","Allow")
            $Acl.AddAccessRule($Ar1)
            $Acl.AddAccessRule($Ar2)
            Set-Acl $DestinationPath $Acl

        }
        
        

    }
    Write-Host ""
    Write-Host "Configuring each services " -ForegroundColor Green

    #Create custom conf file for each user choice, + Creates and start associated service
    foreach($RedisType in $userchoices){
        ConfigureServer $RedisType 
    }

    #Make sure all ports are opened
    Write-Host "Testing ports opening with other Host Servers in the cluster" -ForegroundColor Green
    foreach($RedisType in $userchoices){
        foreach($clu_host in $env:CLU_HOSTS.Split(',')) {
            CheckConnection $clu_host $RedisType.port
        }
    }
}


