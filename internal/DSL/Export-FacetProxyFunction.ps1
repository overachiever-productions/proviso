﻿Set-StrictMode -Version 1.0;

filter Export-FacetProxyFunction {
	
	param (
		[Parameter(Mandatory)]
		[string]$RootDirectory,
		[Parameter(Mandatory)]
		[string]$FacetName,
		[switch]$Provision = $false,
		[switch]$AllowRebase
	);
	
	# NOTE: $script:PVRunbookActive may NOT end up being used... 
	[string]$template = 'Set-StrictMode -Version 1.0;

function {0}-{1} {{
	
	param (
		[Parameter(ValueFromPipelineByPropertyName, ValueFromPipeline)]
		[PSCustomObject]$Config{2}
	);
	
	Validate-MethodUsage -MethodName "{0}";

	if(($global:PVExecuteActive -eq $true) -or ($global:PVRunBookActive -eq $true)) {{
		if($null -eq $Config) {{
			$Config = $global:PVConfig;
		}}
	}}

	Process-Facet -FacetName "{1}" -Config $Config {3}{4};
}}';
		
	
	$rebaseParamDef = "";
	$rebaseOutput = "";
	$provisionDirective = "";
	if ($Provision) {
		$provisionDirective = "-Provision";
		
		if ($AllowRebase) {
			$rebaseParamDef = ",`r`t`t[Switch]`$ExecuteRebase = `$false, `r`t`t[Switch]`$Force = `$false ";
			$rebaseOutput = "-ExecuteRebase:`$ExecuteRebase -Force:`$Force ";
		}
	}
	
	$methodType = "Validate";
	if ($Provision) {
		$methodType = "Provision";
	}
	
	$body = [string]::Format($template, $methodType, $FacetName, $rebaseParamDef, $rebaseOutput, $provisionDirective);
	
	try {
		$filePath = Join-Path -Path $RootDirectory -ChildPath "\facets\generated";
		$filePath = Join-Path -Path $filePath -ChildPath "$methodType-$FacetName.ps1";
		
		Set-Content -Path $filePath -Value $body -NoNewline -Confirm:$false -Force;
	}
	catch {
		
	}
}

#Export-FacetProxyFunction -RootDirectory "D:\Dropbox\Repositories\proviso" -FacetName "ServerName";
#Export-FacetProxyFunction -RootDirectory "D:\Dropbox\Repositories\proviso" -FacetName "ServerName" -ExecuteConfiguration -AllowRebase;