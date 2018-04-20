cd D:/

$list = (D:\elasticsearch\bin\elasticsearch-plugin.bat list)
if($list -notcontains "x-pack") {
    Write-Host "Installing X-Pack in Elastic..." -ForegroundColor Green
    D:\elasticsearch\bin\elasticsearch-plugin.bat install x-pack
}
else {
    Write-Host "X-Pack already installed in Elastic" -ForegroundColor Green
}

$conf = (Get-Content D:\elasticsearch\config\elasticsearch.yml)
if (($conf -match "xpack.security.enabled").Count -eq 0) {
    Write-Host "Updating Elastic config for X-Pack..." -ForegroundColor Green
	# removed as it seems to cause issues
    Add-Content D:\elasticsearch\config\elasticsearch.yml "xpack.security.enabled: false"
}


$listkibana = (D:\kibana\bin\kibana-plugin.bat list)
if (!(( $listkibana -like 'x-pack*').count -eq 1)) {
    Write-Host "Installing X-Pack in Kibana..." -ForegroundColor Green
    D:\kibana\bin\kibana-plugin.bat install x-pack
}
else {
    Write-Host "X-Pack already installed in Kibana" -ForegroundColor Green
}

$conf = (Get-Content D:\kibana\config\kibana.yml)
if (($conf -match "xpack.security.enabled").Count -eq 0) {
    Write-Host "Updating Kibana config for X-Pack..." -ForegroundColor Green
	# removed 
	Add-Content D:\kibana\config\kibana.yml "xpack.security.enabled: false"
}
$Ok = ""
Do {
$Answers = @("Y", "N", "EXIT")
Write-Host ""
Write-Host "Restart ES services? " -ForegroundColor Yellow
Write-Host ""
Write-Host -NoNewline "Y/N > "
$InputResponse= (Read-Host).ToUpper()
$Ok = $Answers -contains $InputResponse
} Until ($Ok)
if ($InputResponse -eq "Y"){
	Get-Service elastic* | Stop-Service
	Get-Service elastic* | Start-Service
	sleep 25
	Get-Service elastic* #Need to be started for license
}

$Ok = ""
Do {
$Answers = @("Y", "N", "EXIT")
Write-Host ""
Write-Host "Do you want to install license? (Only if Xpack already installed on each cluster's node, otherwise you'll get an error) " -ForegroundColor Yellow
Write-Host ""
Write-Host -NoNewline "Y/N > "
$InputResponse= (Read-Host).ToUpper()
$Ok = $Answers -contains $InputResponse
} Until ($Ok)
if ($InputResponse -eq "N"){Exit}

$PathLicenseJson = "\\$env:SQLBACKUP\SLOWSAN\Sources\ElasticSearch\xpack_licenses\*.json"
Write-Host "Cherching for license json file in $PathLicenseJson "
$LatestLicense = Get-Item $PathLicenseJson | Sort-Object -Property LastWriteTime -Descending | Select-Object -first 1 | Get-content
if(!$LatestLicense){ Write-host "License file not found. Download one from https://register.elastic.co/" -ForegroundColor Red
	Exit
}

if ($data){
	Remove-Variable data
}
$data = Invoke-RestMethod http://localhost:39200/_xpack/license?acknowledge=true -Method Put -Body $LatestLicense
# Another Method but with result feedback:
# $response = $LatestLicense  |  Invoke-WebRequest -uri http://localhost:39200/_xpack/license -usebasicparsing -Credential elastic -Method Put

if (($data.acknowledged) -and ($data.license_status -eq "valid")) {
	Write-Host "License installed" -ForegroundColor Green
    $data = Invoke-RestMethod http://$($env:ComputerName):39200/_license
    if($data.license.status -eq "active") {
	    Write-Host "License is active" -ForegroundColor Green
        $ExpiryDateStr = $data.license.expiry_date;
        $ExpiryDate = [DateTime]::ParseExact($ExpiryDateStr, "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'", [CultureInfo]::InvariantCulture);
        if($ExpiryDate.AddDays(-30) -lt (Get-Date)) {
    	    Write-Host "License will expire in less than 30 days" -ForegroundColor Yellow
        }
        else {
            $days = (New-TimeSpan -Start (Get-Date) -End $ExpiryDate).Days;
    	    Write-Host "License will expire in $days days" -ForegroundColor Green
        }
    }
    else {
	    Write-Host "License is not active" -ForegroundColor Yellow
    }
}
else {
	Write-Host "Error installing license" -ForegroundColor Red
	$data.acknowledge
}
#Remark : the Invoke-RestMethod error type "No handler for action ..." is probably due to Xpack no yet being installed on all nodes.