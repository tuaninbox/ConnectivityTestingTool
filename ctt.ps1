#$command=$MyInvocation.MyCommand.Name
$datafile=$args[0]
if ($datafile -eq $null) {
    Write-Host "Version 20210617-1400`r`nUsage: <cmd> <datafile>"
    Exit
}
$TimeNow=(Get-Date).Tostring("yyyyMMdd-hhmm")
$OutFile=$TimeNow+".txt"
Write-Host "Result will be saved to" $OutFile "in the same folder"


$ListofInt = Get-NetIPInterface | ? {($_.ConnectionState -eq "Connected") -And ($_.AddressFamily -like "IPv4") -and $_.InterfaceAlias -notlike "*Pseudo*"}

$HostInfo="============ Host Information =============="
Write-Host $HostInfo
Add-Content $OutFile $HostInfo

$SearchList = Get-DnsClientGlobalSetting | Select SuffixSearchList
$DNSServerLocal = ""
$ListofInt | ForEach-Object {
    $IPAddress = Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex | ? {$_.AddressFamily -like "IPv4"}
    $DNSServer = Get-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex | Where-Object {$_.AddressFamily -eq 2} 
    $Route = Get-NetRoute -InterfaceIndex $_.InterfaceIndex | ? {$_.DestinationPrefix -like "0.0.0.0/0"} | select NextHop,RouteMetric
    $Output = "----------"
    $Output = $Output + "`r`nInterface: " + $IPAddress.InterfaceAlias
    $Output = $Output + "`r`nIP Address: " + $IPAddress.IPAddress + "/"+ $IPAddress.PrefixLength
    $Output = $Output + "`r`nDNS Servers: " + $DNSServer.ServerAddresses
    $Output = $Output + "`r`nDefault Gateway: " + $Route.NextHop + " Metric: " + $Route.RouteMetric
    Write-Host $Output
    Add-Content $OutFile $Output
    #$DNSServerLocal = $DNSServerLocal + $DNSServer.ServerAddresses + " "
    $DNSServerLocal = $DNSServer.ServerAddresses
    $DNSServerLocal | ForEach-Object {
        $r = Resolve-DNSName google.com -server $_ -WarningAction:Silent 2>&1 | out-null
        if ($? -eq $true) {
            $Output = "DNS Server " + $_ + " is accessible"
        }
        else {
            $Output = "DNS Server " + $_ + " is INACCESSIBLE"
        }
        if ($Output -match "INACCESSIBLE"){
            Write-Host $Output -ForegroundColor Red
        }
        else {
            Write-Host $Output -ForegroundColor Green
        }
        Add-Content $OutFile $Output
    }
    if ($Route.NextHop -ne $null) {
        $r = Test-NetConnection -computer $Route.NextHop -WarningAction:Silent
        if ($r.PingSucceeded -eq $true) {
            $Output = "Default GW" + " - " + $Route.NextHop + " is reachable"
        }
        else {
            $Output = "Default GW" + " - " + $Route.NextHop + " is UNREACHABLE"
        }
        if ($Output -match "UNREACHABLE"){
            Write-Host $Output -ForegroundColor Red
        }
        else {
            Write-Host $Output -ForegroundColor Green
        }
        Add-Content $OutFile $output
    }
}
    $Output = "----------"
    $Output = $Output + "`r`nDomain Search List: " + $SearchList.SuffixSearchList
    Write-Host $Output
    Add-Content $OutFile $Output
   

$Title="`r`n========== Running Test Script @ " + $TimeNow +"============="
Write-Host $Title
Add-Content $OutFile $Title
 
Import-Csv $datafile | ForEach-Object {
    if ($_.type -eq "ping") {
        $r = Test-NetConnection -computer $_.address -WarningAction:Silent
        if ($r.PingSucceeded -eq $true) {
            $Output = $_.name + " - " + $_.address + " is reachable"
        }
        else {
            $Output = $_.name + " - " + $_.address + " is UNREACHABLE"
        }
        $Delimiter = "`r`n------------- " + $_.type + " --------------`r`n"
        Write-Host $Delimiter
        if ($Output -match "UNREACHABLE"){
            Write-Host $Output -ForegroundColor Red
        }
        else {
            Write-Host $Output -ForegroundColor Green
        }
        Add-Content $OutFile $output

    }
    elseif ($_.type -eq "ssh") {
        $r = Test-NetConnection -computer $_.address -Port 22 -WarningAction:Silent
        if ($r.TcpTestSucceeded -eq $true) {
            $Output = $_.name + " - " + $_.address + " port 22 is reachable"
        }
        else {
            $Output = $_.name + " - " + $_.address + " port 22 is UNREACHABLE"
        }
        $Delimiter = "`r`n------------- " + $_.type + " --------------`r`n"
        Write-Host $Delimiter
        if ($Output -match "UNREACHABLE"){
            Write-Host $Output -ForegroundColor Red
        }
        else {
            Write-Host $Output -ForegroundColor Green
        }
        Add-Content $OutFile $output

    }
    elseif ($_.type -eq "trace") {
        $r = Test-NetConnection -ComputerName $_.address -TraceRoute
        $Output = "Trace to " + $_.name + " - " + $_.address + ". Path is: `n"
        $r.TraceRoute | foreach { $Output+=$_+"`n" }
        $Output += "RTT: " + ($r | Select -expandproperty PingReplyDetails).RoundtripTime + " ms"
        $Output = "`r`n------------- " + $_.type + " --------------`r`n" + $output
        Write-Host $Output
        Add-Content $OutFile $Output
    }
    elseif ($_.type -eq "dns") {
        $r = Resolve-DNSName $_.address
        if ($? -eq $true -and $_.expect -eq $null) {
            $Output = "DNS Resolution for " + $_.name + " - " + $_.address + " is OK. Resolved to " + $r.IPAddress
        }
        elseif ($r.IPAddress -eq $_.expect) {
            $Output = "DNS Resolution for " + $_.name + " - " + $_.address + " is OK. Resolved to " + $r.IPAddress
        }
        elseif ($r.IPAddress -ne $_.expect) {
            $Output = "DNS Resolution for " + $_.name + " - "+ $_.address + " is NOT GOOD. Resolved to " + $r.IPAddress + ", but it should be " + $_.expect
        }
        $Delimiter = "`r`n------------- " + $_.type + " --------------`r`n"
        write-host $Delimiter
        if ($Output -match "NOT GOOD") {
            Write-Host $Output -ForegroundColor Red
        }
        else {
            Write-Host $Output -ForegroundColor Green
        }
        Add-Content $OutFile $output
    }
    elseif ($_.type -eq "web") {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
            $r = Invoke-WebRequest $_.address -WarningAction:Silent
            if ($r.statusCode -eq 200) {
                $Output = $_.name + " @ " + $_.address + " is accessible" 
            }
            else {
                $Output = $_.name + " @ " + $_.address + " is INACCESSIBLE"
            }
            Write-Host $_.Exception.Response.StatusCode.Value__
        }
        catch {
            $Output = $_.Exception
        }
        
       
        $Delimiter = "`r`n------------- " + $_.type + " --------------`r`n"
        write-host $Delimiter
        if ($Output -match "accessible"){
            Write-Host $Output -ForegroundColor Green
        }
        else {
            Write-Host $Output -ForegroundColor Red
        }
        Add-Content $OutFile $Output
    }
}

