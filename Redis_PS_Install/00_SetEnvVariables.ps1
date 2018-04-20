
# This script sets up two env variables for Redis Cluster
# These are 'guessed' from :
#    - the servers naming convention (01,02,03,...)
#    - the name of current machine 
#    - the number of computer in the cluster 


If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "Please run this as Administrator!"
    Exit
}

#Check if var already setup
IF($env:CLU_HOSTS -ne $null -and $env:CLU_NAME -ne $null)
{
	Write-Host "Env variables already setup" -ForegroundColor Green
    $response = Read-host "Exit? (y/n)"
    if (-not($response -eq 'n')){
		Exit
    }
}

$DNSName = $env:ComputerName


Write-Host "How many computers will be in this cluster? (put 1 if not a cluster)"
Write-Host ">" -NoNewLine
$nb_machines_in_cluster = (Read-Host)
#---------------------------------------------------
$hosts = ''
if ($nb_machines_in_cluster -eq 1 ) {
	$hosts=$DNSName
}
else {
	For ($i=1; $i -le $nb_machines_in_cluster; $i++) {
		if( $i-gt 1){
			$hosts+=','
		}
		$hosts+=$DNSName.substring(0, $DNSName.Length-1) +$i
	}
}
$clu_name=$DNSName.substring(0, $DNSName.Length-2)+"CLU"

Write-Host "Supposed Cluster Name :"
Write-Host $clu_name -ForegroundColor Magenta
Write-Host "Supposed hosts names in cluster :"
try{
	#Display machines and try to find their ips
	foreach($hostname in ($hosts.split(',')))
	{
		$DiscoverIp = [System.Net.Dns]::GetHostAddresses($hostname) | Where-Object {$_.AddressFamily -eq 'InterNetwork'} | Select-Object -Last 1
		Write-Host "$hostname : $($DiscoverIp.IPAddressToString)" -ForegroundColor Magenta
	}
	Write-Host "(correct script if wrong)"
}
catch{}

if ( $hosts -notlike ("*$env:ComputerName*")) {
	Throw "Unexpected computer name: "+$env:ComputerName
}
else {
	[Environment]::SetEnvironmentVariable("CLU_HOSTS", $hosts, "Machine") 
	[Environment]::SetEnvironmentVariable("CLU_NAME" , $clu_name, "Machine")   
}

Write-Host "Env variables set (restart powershell or reboot server to apply) " -ForegroundColor Green


