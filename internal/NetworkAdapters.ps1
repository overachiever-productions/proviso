Set-StrictMode -Version 1.0;

filter Get-ExistingNetAdapters {
	<#
		NOTE: without explicitly casting the output to [PSCustomObject], the following: 
				> $x = Get-ExistingNetAdapters;
				> Write-Host "x = $x " ... 
		Will yield: 
				"x = "
			i.e., not sure at all what's going on with .ToString() on CimInstance details or whatever... 
			So, capturing output + returning as a [PSCustomObject] seems to fix this issue.

	#>	
	$adapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, @{
		Name = "Index"; Expression = {
			$_.ifIndex
		}
	}, Status;
	
	return [PSCustomObject]$adapters;
}

filter Get-ExistingIpConfigurations {
	$data = Get-NetIPConfiguration | Select-Object @{
		Name			  = "Name"; Expression = {
			$_.InterfaceAlias
		}
	},
												   @{
		Name				    = "Description"; Expression = {
			$_.InterfaceDescription
		}
	}, @{
		Name			  = "Index"; Expression = {
			$_.InterfaceIndex
		}
	}, IPv4Address, IPv4DefaultGateway, DNSServer, "NetProfile.Name";
	
	return [PSCustomObject]$data;
}

filter Set-AdapterDnsAddresses {
	param (
		[Parameter(Mandatory)]
		[int]$AdapterIndex,
		[Parameter(Mandatory)]
		$PrimaryDnsAddress,
		$SecondaryDnsAddress = $null
	);
	
	[string[]]$dnsServerAddresses = @();
	$dnsServerAddresses += $PrimaryDnsAddress;
	
	if ($null -ne $SecondaryDnsAddress) {
		$dnsServerAddresses += $SecondaryDnsAddress;
	}
	
	Set-DnsClientServerAddress -InterfaceIndex $AdapterIndex -ServerAddresses ($dnsServerAddresses) | Out-Null;
}

filter Set-AdapterIpAddressAndGateway {
	param (
		[Parameter(Mandatory)]
		[int]$AdapterIndex,
		[Parameter(Mandatory)]
		$CidrIpAddress,
		[Parameter(Mandatory)]
		$GatewayIpAddress
	);
	
	# Sadly, IP config via POSH is a bit ugly - need to remove IP and routes then reset. 
	# 		See this for more info: https://etechgoodness.wordpress.com/2013/01/18/removing-an-adapter-gateway-using-powershell/ 
	
	[string[]]$ipParts = $CidrIpAddress -split "/";
	
	Remove-NetIPAddress -InterfaceIndex $AdapterIndex -Confirm:$false | Out-Null;
	Remove-NetRoute -InterfaceIndex $AdapterIndex -DestinationPrefix 0.0.0.0/0 -Confirm:$false | Out-Null;
	
	New-NetIPAddress -InterfaceIndex $AdapterIndex -IPAddress $ipParts[0] -PrefixLength $ipParts[1] -DefaultGateway $GatewayIpAddress | Out-Null;
}