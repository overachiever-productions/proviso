﻿Set-StrictMode -Version 1.0;

filter Clear-FacetProxies {
	param (
		[Parameter(Mandatory)]
		[string]$RootDirectory
	);
	
	try {
		[string]$proxypath = Join-Path -Path $RootDirectory -ChildPath "\facets\generated";
		[string]$targetPath = "$($proxypath)\*.ps1";
		
		Remove-Item -Path $targetPath -Recurse -Confirm:$false -Force;
	}
	catch {
		throw "Exception clearing Generated Facets in $targetPath. `rException: $_ `r`t$($_.ScriptStackTrace)";
	}
}

#Clear-FacetProxies -RootDirectory "D:\Dropbox\Repositories\proviso";