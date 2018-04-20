#In progress
#Configure pre installed redis services in cluster(script 01)
#Make sure these are also installed and started on all Nodes of the cluster

############ PARAMS ###########
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "Please run this as Administrator!"
    Exit
}
cd D:/

$FlushPrevKeys = 0 #Put 1 only if you want to flush all previous data (of the selected clusters only)
$ClusterReset = 1 #Can be left to 1. SET to 1 to perform a cluster reset before the new config. This will fail if there are values in the cluster and Flush = 0


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

Write-Host "Make sure these services are also running on the other nodes !" -ForegroundColor Yellow

######  AUTO DEFINE CLUSTER SERVERS ############

#foreach($hostname in ($env:clu_hosts.split(',')))
#{
#    # Note : this needs the nodes to be running and accessible !
#      $DiscoverIp = [System.Net.Dns]::GetHostAddresses($hostname) | Where-Object {$_.AddressFamily -eq 'InterNetwork'}
#      Write-Host "$hostname : $($DiscoverIp.IPAddressToString)" 
#      $lastTwoCharsOfComputerName = $hostname.Substring($hostname.Length - 2)
#      $ThisNode=(
#        [PSCustomObject]@{
#        HostName = $hostname
#        HostIp = $DiscoverIp
#        NodeId = [int]$lastTwoCharsOfComputerName
#       })
#       $clu_hosts+=$ThisNode
#
#    if ($hostname -eq $env:COMPUTERNAME)
#    {
#        $LocalNode = $ThisNode
#        Write-Host "(local node)"
#    }
#}


$userchoices = ($TypesOfRedis | out-gridview -Title "Chose a running Redis to configure in cluster"  -passthru)




#function to configure MASTER  from server object 
function ConfigureClusterMaster{
    Param ([PSCustomObject]$RedisType, [String]$Master_host)
    
    $Host_NodeId =  [int]($Master_host.Substring($Master_host.Length - 2))
    $Master_IP = [System.Net.Dns]::GetHostAddresses($Master_host)  | Where-Object {$_.AddressFamily -eq 'InterNetwork'}

    cd "D:/Redis_$($RedisType.Env)"
    
    Write-Host "Discovering Master node  $Master_host  $($RedisType.port)"  -ForegroundColor Green
    $response = ./redis-cli.exe -c -p $RedisType.port cluster meet $Master_IP  $RedisType.port
    if ( $response -eq 'OK')   {
        Write-host $response -ForegroundColor Green
    }
    else  {
        Write-host $response -ForegroundColor Red
        Write-host "( ./redis-cli.exe -c -p $($RedisType.port) cluster meet $Master_IP  $($RedisType.port) )"
    }

       
    $MaxSlots = 16384 #actually it's 16383 but the last is not included
    $SlotsPerNode = ($MaxSlots+3)/$clu_hosts.Length
    $slotStart = [int](($Host_NodeId -1)*$SlotsPerNode)
    $slotEnd = [int](($Host_NodeId)*$SlotsPerNode)
    if($slotEnd -gt $MaxSlots){
        $slotEnd = $MaxSlots
    }
      
    Write-Host "Assigning slots (include) $slotStart - $slotEnd (exclude) to $($Master_host) " -ForegroundColor Green

    $SlotstoAddString= ''
    for ($i=$slotStart; $i -lt $slotEnd; $i++){
        $SlotstoAddString +=" "+$i
        if (($SlotstoAddString.length -gt 9000) -or ($i -eq $slotEnd-1))  #Avoid error when string too long
        {
            $CmdCluSlots = "./redis-cli.exe -h $Master_host -p $($RedisType.port) CLUSTER ADDSLOTS $SlotstoAddString"
            iex $CmdCluSlots
            $SlotstoAddString = ''
        }
    }
            
}
#function to configure file from server object
function ConfigureClusterSlave{
    Param ([PSCustomObject]$RedisType, [String]$Slave_host)
    
    $Host_NodeId =  [int]($Slave_host.Substring($Slave_host.Length - 2))
    $Slave_IP =[System.Net.Dns]::GetHostAddresses($Slave_host)  | Where-Object {$_.AddressFamily -eq 'InterNetwork'} 

    cd "D:/Redis_$($RedisType.Env)"
    $masterPort = [math]::Round($RedisType.port/10)*10
    
    #CLUSTER MEET
    Write-Host "Discovering Slave Node  $Slave_host $Slave_IP : $($RedisType.port)"  -ForegroundColor Green
    $response = ./redis-cli.exe -c -p $masterPort cluster meet $Slave_IP $($RedisType.port)
    if ( $response -eq 'OK')   {
        Write-host $response -ForegroundColor Green
    }
    else  {
        Write-host $response -ForegroundColor Red
        Write-host "( ./redis-cli.exe -c -p $masterPort cluster meet $Slave_IP  $($RedisType.port) )"
    }



    #Set which Master node is linked to this slave
    if($Host_NodeId -gt 1 ){
        $Expected_MasterNodeID = ($Host_NodeId-1)
    }
    elseif ($Host_NodeId -eq 1 ){
        $Expected_MasterNodeID = $clu_hosts.length
    }
    foreach ($MasterHost in $clu_hosts){
        $Master_NodeId =  [int]($MasterHost.Substring($MasterHost.Length - 2))
        if($Master_NodeId -eq $Expected_MasterNodeID){
           $Master_Hostname = $MasterHost
           $Master_IP = [System.Net.Dns]::GetHostAddresses($Master_Hostname) | Where-Object {$_.AddressFamily -eq 'InterNetwork'}
           $Master_port = [math]::Round($RedisType.port/10)*10
           break;
        }
    }
    
    #$masterhost  is the host associated to this slave
    
    sleep 1 #sleeping to let time for nodes to appear 

    #This next commands returns all nodes details for the cluster. We need the master node GUID for this slave
    #see redis.io for details
    $clu_nodes_details = ./redis-cli.exe -h $Slave_host -p $RedisType.port CLUSTER NODES
    $MasterNodeGuid = ''
    #extract the correct guid from prev command results
    foreach ($node_details in $clu_nodes_details.split('\n')){
        if ($node_details -like "*$($Master_IP):$Master_port*")
        {
            $MasterNodeGuid = $node_details.split(' ')[0]
            break;
        }
    }

    if($MasterNodeGuid -eq ''){
        Write-Host NodeGuid for the master not found: -ForegroundColor Red
        "Expected to find Master ip *$($Master_IP):$Master_port*"
        "In Node details : ./redis-cli.exe -h $Slave_host -p $($RedisType.port) CLUSTER NODES "
        $clu_nodes_details.split('\n')
    }

    Write-Host "Replicate master $($Master_Hostname):$Master_port ($MasterNodeGuid) to slave $($Slave_host):$($RedisType.Port)"  -ForegroundColor Green
    ./redis-cli.exe -h $Slave_host -p $RedisType.port CLUSTER REPLICATE $MasterNodeGuid

}

#Make sure FlushPrevKeys is Active on purpose
if ($FlushPrevKeys)
{
    Do {
	    $Ok = $FALSE
	    Write-Host FlushPrevKeys is ON.  -ForegroundColor Magenta
        Write-Host Are you sure you want to perform a Flush of possibly existing keys for selected clusters? :  -ForegroundColor Magenta
        Write-Host "Y/N ?" -ForegroundColor Yellow
	    $res = (read-host).ToUpper()
	    $Ok = @("Y", "N") -contains $res
    } Until ($Ok)
    if ($res -eq "N"){
    Exit
    }
}



#Performs flush of keys if active
#Perform cluster reset SLAVE + master (forget nodes, master, key slots..). But does not work if keys inserted
if($ClusterReset -eq 1){
    foreach($RedisType in $userchoices){
        foreach ($clu_host in $clu_hosts){
                if($ClusterReset -eq 1){
                    cd "D:/Redis_$($RedisType.Env)"
                    if ($FlushPrevKeys -and $RedisType.Master_Slave -eq 'Master'){
                        #flush done only on masters
                        #If flush is off and redis contains keys, the RESET will fail
                        ./redis-cli.exe -c -h $clu_host -p $RedisType.port FLUSHALL
                    }
                    ./redis-cli.exe -c -h $clu_host -p $RedisType.port CLUSTER RESET HARD
                    Write-Host "CLUSTER RESET of for cluster $($RedisType.Env) $($RedisType.RedisType) $($RedisType.Master_Slave) $clu_host" -ForegroundColor Green
                }
        }
    }
   
}


#Configure Masters First
foreach ($Master in ($userchoices| Where-Object {$_.Master_Slave -eq 'Master'}) ){
    #Configure the 3 masters of the cluster at the same time
    foreach ($clu_host in $clu_hosts){
        #Configure masters
        ConfigureClusterMaster $Master $clu_host
    }
}
sleep 2 #give time to master nodes to meet each other
Write-host ""
Write-host "Masters conf done!" -ForegroundColor Green

#Configure Slaves Second
foreach ($Slave in ($userchoices| Where-Object {$_.Master_Slave -eq 'Slave'}) ){
    #Configure the 3 slaves of the cluster at the same time
    foreach ($clu_host in $clu_hosts){
        #Configure masters
        ConfigureClusterSlave $Slave $clu_host
    }
}


sleep 2
"Final check"
#Check Cluster state
foreach ($service in ($userchoices)){
    foreach ($clu_host in $clu_hosts){
        cd "D:/Redis_$($service.Env)"
        $Clustate = ./redis-cli.exe -c -h $clu_host -p $service.port CLUSTER INFO
        $msgcolor = 'Red'
        if ($Clustate[0] -eq 'cluster_state:ok'){
            $msgcolor = 'Green'
        }
        Write-Host "$($Clustate[0])  for $($service.Env) $($service.RedisType) $($service.Master_Slave) $clu_host" -ForegroundColor $msgcolor
    }
	
	"Searching for CLUSTER INFO cluster_known_nodes . Expected : "+($clu_hosts.length*2)+" nodes"
	if ($($service.Master_Slave) -eq 'Slave'){
		cd "D:/Redis_$($service.Env)"
        $Clustate = ./redis-cli.exe -c -p $service.port CLUSTER INFO
		 $msgcolor = 'Red'
        if ($Clustate[10] -eq 'cluster_known_nodes:'+($clu_hosts.length*2)){
            $msgcolor = 'Green'
        }
        Write-Host "$($Clustate[10])  for $($service.Env) $($service.RedisType) $($service.Master_Slave) localhost" -ForegroundColor $msgcolor
	}
	
	if ($msgcolor  = 'Green' -and $($service.Master_Slave) -eq 'Master'){
		Write-Host "Testing the insert and deletion of keys for $($service.Env) $($service.RedisType) $($service.Master_Slave) localhost" -ForegroundColor Green
		cd "D:/Redis_$($service.Env)"
		
		./redis-cli.exe -c -p $service.port set init_test OK!
		./redis-cli.exe -c -p $service.port set init_test2 OK!
		./redis-cli.exe -c -p $service.port set init_test3 OK!
		./redis-cli.exe -c -p $service.port get init_test
		./redis-cli.exe -c -p $service.port get init_test2
		./redis-cli.exe -c -p $service.port get init_test3
		./redis-cli.exe -c -p $service.port del init_test
		./redis-cli.exe -c -p $service.port del init_test2
		./redis-cli.exe -c -p $service.port del init_test3
	}
	
}