Set-StrictMode -Version 1.0;

<#

	Import-Module -Name "D:\Dropbox\Repositories\proviso\" -DisableNameChecking -Force;
	Map -ProvisoRoot "\\storage\Lab\proviso\";
	Target -ConfigFile "\\storage\lab\proviso\definitions\PRO\PRO-197.psd1" -Strict:$false;

	#Target -ConfigFile "\\storage\lab\proviso\definitions\PRO\SQL-150-AG01A.psd1" -Strict:$false;
	#Target -ConfigFile "\\storage\lab\proviso\definitions\MeM\mempdb1b.psd1" -Strict:$false;

	#Validate-NetworkAdapters;
	#Validate-WindowsPreferences;
	#Validate-RequiredPackages;
	#Validate-HostTls;
	#Validate-FirewallRules; 
	#Validate-ExpectedDisks;
	#Validate-SqlInstallation;
	#Validate-SqlConfiguration;
	#Validate-ExpectedDirectories;
	#Validate-ExpectedShares;
	#Validate-SsmsInstallation;

	#Validate-AdminDbInstanceSettings;
	#Validate-AdminDbDiskMonitoring;

	Validate-ExtendedEvents;
	#Validate-SqlVersion;	
	
	Validate-ClusterConfiguration;

	Summarize;

#>

filter Get-SqlInstanceNameForDynamicFacets {
	param (
		[string]$CurrentInstanceName,
		[string[]]$TargetInstances
	);
	
	if (("MSSQLSERVER" -eq $CurrentInstanceName) -and ($TargetInstances.Count -lt 2)) {
		return "";  # i.e., no need to append 'MSSQLSERVER' to Dynamic Facet Names if/when it's the ONLY instance... 
	}
	
	return $CurrentInstanceName;
}

filter New-DynamicFacet {
	param (
		[Proviso.Models.Facet]$BaseFacet,
		[string]$ChildName,
		[string]$SubChildName,
		[string]$SqlInstanceName,
		[string]$ObjectName
	);
	
	$facetName = $BaseFacet.Name;
	if (-not ([string]::IsNullOrEmpty($ChildName))) {
		$facetName = "$($facetName).$($ChildName)";
	}
	if (-not ([string]::IsNullOrEmpty($SubChildName))) {
		$facetName = "$($facetName)-$($SubChildName)";
	}
	
	$key = $BaseFacet.Key;
	if (-not ([string]::IsNullOrEmpty($SqlInstanceName))) {
		$key = $key -replace "{~SQLINSTANCE~}", $SqlInstanceName;
	}
	if (-not ([string]::IsNullOrEmpty($ObjectName))) {
		$key = $key -replace "{~ANY~}", $ObjectName;
	}
	$newFacet = New-Object Proviso.Models.Facet(($BaseFacet.Parent), $facetName, $BaseFacet.FacetType, $key);
	
	if ($null -eq $BaseFacet.Expect) {
		$script = $null;
		if ($BaseFacet.ExpectsKeyValue) {
			$script = "return `$PVConfig.GetValue(`"$key`");";
		}
		elseif ($BaseFacet.ExpectCurrentIterationKey) {
			# Note, these SHOULD always be strings: 
			if ($BaseFacet.FacetType -eq "SqlObject") {
				$script = "return '$SqlInstanceName';";
			}
			else {
				$script = "return '$ObjectName'";
			}
		}
		
		$expectedBlock = [ScriptBlock]::Create($script);
		$newFacet.SetExpect($expectedBlock);
	}
	else {
		$newFacet.SetExpect($BaseFacet.Expect);
	}
	
	$newFacet.SetTest($BaseFacet.Test);
	$newFacet.SetConfigure($BaseFacet.Configure, $BaseFacet.UsesBuild);
	
	if (-not ([string]::IsNullOrEmpty($SqlInstanceName))) {
		$newFacet.CurrentSqlInstanceName = $SqlInstanceName;
	}
	
	if (-not ([string]::IsNullOrEmpty($ObjectName))) {
		$newFacet.CurrentObjectName = $ObjectName;
	}
	
	$newFacet.CurrentKey = $key;
	if (-not ([string]::IsNullOrEmpty($key))) {
		if ($newFacet.FacetType -in @("SimpleArray", "ObjectArray", "SqlObjectArray", "CompoundArray")) {
			$newFacet.CurrentKeyValue = $ObjectName; # otherwise, we get the 'array' of values (which... might make sense but I don't THINK it does... )
		}
		else {
			$newFacet.CurrentKeyValue = $PVConfig.GetValue($key);
		}
	}
	
	return $newFacet;
}

function Process-Surface {
	param (
		[Parameter(Mandatory)]
		[string]$SurfaceName,
		[Parameter(Mandatory)]
		[ValidateSet("Validate", "Configure", "Describe")]
		[string]$Operation = "Validate",
		[switch]$ExecuteRebase = $false,
		[switch]$Force = $false
	);
	
	begin {
		Validate-Config;
		Validate-MethodUsage -MethodName "Process-Surface";
		
		$surface = $global:PVCatalog.GetSurface($SurfaceName);
		if ($null -eq $surface) {
			throw "Invalid Surface Name. Surface [$SurfaceName] does not exist or has not yet been loaded. If this is a custom Surface, verify that [Import-Surface] has been executed.";
		}
		
		if ($ExecuteRebase) {
			if (-not ($Force)) {
				throw "Invalid -ExecuteRebase inputs. Because Rebase CAN be detrimental, it MUST be accompanied with the -Force [switch] as well.";
			}
		}
		
		$executeConfiguration = ("Configure" -eq $Operation);
		$surfaceProcessingResult = New-Object Proviso.Processing.SurfaceProcessingResult($surface, $executeConfiguration);
		$processingGuid = $surfaceProcessingResult.ProcessingId;
		$PVContext.SetCurrentSurface($surface, $ExecuteRebase, $executeConfiguration, $surfaceProcessingResult);
	}
	
	process {
		# --------------------------------------------------------------------------------------
		# Setup	
		# --------------------------------------------------------------------------------------
		if ($surface.Setup.SetupBlock) {
			try {
				[ScriptBlock]$setupBlock = $surface.Setup.SetupBlock;
				
				& $setupBlock;
			}
			catch{
				$PVContext.WriteLog("FATAL: Surface.Setup FAILED for Surface [$($surface.Name)]. Error Detail: $($_)", "Critical");
			}
		}
		
		# --------------------------------------------------------------------------------------
		# Assertions	
		# --------------------------------------------------------------------------------------
		$assertionsFailed = $false;
		if ($surface.Assertions.Count -gt 0) {
			
			$surfaceProcessingResult.StartAssertions();
			$results = @();
			
			$assertionsOutcomes = [Proviso.Enums.AssertionsOutcome]::AllPassed;
			foreach ($assert in $surface.Assertions) {
				$assertionResult = New-Object Proviso.Processing.AssertionResult($assert, $processingGuid);
				$results += $assertionResult;
				
				if ($assert.IsIgnored) {
					$PVContext.WriteLog("Skipping Assertion: [$($assert.Name)] because it has been set to [Ignored].", "Debug");
					continue;
				}
				if ($assert.AssertOnConfigureOnly -and ($Operation -eq "Validate")) {
					$PVContext.WriteLog("Skipping Assertion: [$($assert.Name)] because it has been marked [AssertOnConfigureOnly] and current operation is [$Operation].", "Debug");
					continue;
				}
				
				try {				
					[ScriptBlock]$codeBlock = $assert.ScriptBlock;
					$output = & $codeBlock;
					
					if ($null -eq $output) {
						$output = $true;
					}
					
					if ($assert.IsNegated) {
						$output = (-not $output);
					}
					
					$assertionResult.Complete($output);
				}
				catch {
					$assertionResult.Complete($_);
				}
				
				if ($assertionResult.Failed) {
					if ($assert.NonFatal) {
						$assertionsOutcomes = [Proviso.Enums.AssertionsOutcome]::Warning;
						$PVContext.WriteLog("WARNING: Non-Fatal Assertion [$($assert.Name)] Failed. Error Detail: $($assertionResult.GetErrorMessage())", "Important");
					}
					else {
						$assertionsFailed = $true;
						$PVContext.WriteLog("FATAL: Assertion [$($assert.Name)] Failed. Error Detail: $($assertionResult.GetErrorMessage())", "Critical");
					}
				}
			}
			
			if ($assertionsFailed) {
				$surfaceProcessingResult.EndAssertions([Proviso.Enums.AssertionsOutcome]::HardFailure, $results);
				
				$surfaceProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentSurface();
				
				return; 
			}
			else {
				$surfaceProcessingResult.EndAssertions($assertionsOutcomes, $results);
			}
		}
		
		# --------------------------------------------------------------------------------------
		# Facet Aseembly
		# --------------------------------------------------------------------------------------
		$facets = @();
		
		$simpleFacets = $surface.GetSimpleFacets();
		foreach ($simpleFacet in $simpleFacets) {
			if ($simpleFacet.ExpectsKeyValue) {
				
				$script = "return `$PVConfig.GetValue(`"$($simpleFacet.Key)`");";
				$expectedBlock = [ScriptBlock]::Create($script);
				$simpleFacet.SetExpect($expectedBlock);
				
				$simpleFacet.CurrentKey = $simpleFacet.Key;
				$simpleFacet.CurrentKeyValue = $PVConfig.GetValue($simpleFacet.Key);
			}
			
			$facets += $simpleFacet;
		}
		
		$simpleArrayFacets = $surface.GetSimpleArrayFacets();
		if ($simpleArrayFacets) {
			foreach ($arrayFacet in $simpleArrayFacets) {
				$values = @($PVConfig.GetValue($arrayFacet.Key));
				foreach ($value in $values) {
					$facets += New-DynamicFacet -BaseFacet $arrayFacet -SubChildName $value -ObjectName $value;
				}
			}
		}
		
		$objectFacets = $surface.GetObjectFacets();
		if ($objectFacets) {
			foreach ($objectFacet in $objectFacets) {
				$objects = @($PVConfig.GetObjects($objectFacet.Key));
				
				# TODO: implement sort-order stuff... (might need to actually 'move' this logic up into the call to $PVConfig.GetObjects ... as that might make more sense as a place to do the sort by CHILD key stuff.	
				#$descending = $false;
				#$prop = "Name";
				foreach ($objectName in $objects) { # | Sort-Object -Property $prop -Descending:$descending) {
					$facets += New-DynamicFacet -BaseFacet $objectFacet -SubChildName $objectName -ObjectName $objectName;
				}
			}
		}
		
		$sqlInstanceFacets = $surface.GetSqlInstanceFacets();
		if ($sqlInstanceFacets) {
			
			# NOTE: Nested Loops. This will do A. Each Facet by, B. each SQL Instance. Arguably, it MIGHT make more sense to do each 1. Each SqlInstance, and 2. each/all Facets. 
			# 		BUT, that logic actually becomes a) a LOT harder (the nesting of loops becomes 'stupid tedious') and, more importantly: b) there's no 1000% guarantee that the 
			# 			same number of SQL Instances will be defined from ONE Facet to the NEXT (i.e., a Surface COULD check in 2 or 3 'root'/surface key/areas ... with diff configs)
			foreach ($instanceFacet in $sqlInstanceFacets) {
				
				$sqlInstances = @(($PVConfig.GetSqlInstanceNames($instanceFacet.Key)));
				if ($sqlInstances.Count -lt 1) {
					# TODO: throw UNLESS there's a -SkipIFNoSqlInstance (needs a better name) switch defined. (Which MAY or may not make sense to implement - I've toyed with the idea in the past).
					throw "Not Implemented Yet.";
				}
				
				if ($instanceFacet.FacetType -eq "SqlObject") {
					foreach ($sqlInstance in $sqlInstances) {
						$instanceName = Get-SqlInstanceNameForDynamicFacets -CurrentInstanceName $sqlInstance -TargetInstances $sqlInstances;
						
						$facets += New-DynamicFacet -BaseFacet $instanceFacet -ChildName $instanceName -SqlInstanceName $sqlInstance;
					}
				}
				else { 	# we're dealing with a SqlObjectArray - i.e., TraceFlags (> 1 key value per each SQL Server instance)
					foreach ($sqlInstance in $sqlInstances) {
						$instanceName = Get-SqlInstanceNameForDynamicFacets -CurrentInstanceName $sqlInstance -TargetInstances $sqlInstances;
						$instanceKey = $instanceFacet.Key -replace "{~SQLINSTANCE~}", $sqlInstance;
						$instanceArrayValues = $PVConfig.GetValue($instanceKey);
						
						foreach ($arrayValue in $instanceArrayValues) {
							$facets += New-DynamicFacet -BaseFacet $instanceFacet -SqlInstanceName $sqlInstance -ObjectName $arrayValue -ChildName $instanceName -SubChildName $arrayValue;
						}
					}
				}
			}
		}
		
		$compoundFacets = $surface.GetCompoundFacets();
		if ($compoundFacets) {
			foreach ($compoundFacet in $compoundFacets) {
				$sqlInstances = @(($PVConfig.GetSqlInstanceNames($compoundFacet.Key)));
				foreach ($sqlInstance in $sqlInstances) {
					$instanceName = Get-SqlInstanceNameForDynamicFacets -CurrentInstanceName $sqlInstance -TargetInstances $sqlInstances;
					
					if (Is-InstanceGlobalComplexKey -Key $compoundFacet.Key) {
						if ($compoundFacet.FacetType -eq "Compound") {
							$facets += New-DynamicFacet -BaseFacet $compoundFacet -SqlInstanceName $sqlInstance -ChildName $instanceName;
						}
						else {
							$arrayValues = @($PVConfig.GetValues($compoundFacet.Key));
							foreach ($arrayValue in $arrayValues) {
								$facets += New-DynamicFacet -BaseFacet $compoundFacet -SqlInstanceName $sqlInstance -ChildName $instanceName -SubChildName $arrayValue;
							}
						}
					}
					else {
#Write-Host "Compound Key: $($compoundFacet.Key) "
						
	# call to objects is busted. the compound key above is perfect. 
	#   but the call into GetObjects is returning SQL Server instances - not objects... 					
						$objects = @($PVConfig.GetObjects($compoundFacet.Key));
						
						if ("Compound" -eq $compoundFacet.FacetType) {
							foreach ($objectName in $objects) {
#		Write-Host "	Object: $objectName"						
								$facets += New-DynamicFacet -BaseFacet $compoundFacet -SqlInstanceName $sqlInstance -ObjectName $objectName -ChildName $instanceName -SubChildName $objectName;
							}
						}
						else {
							# CompoundArray
							foreach ($objectName in $objects) {
								$arrayValues = @($PVConfig.GetValues($compoundFacet.Key));
								foreach ($arrayValue in $arrayValues) {
									# Hmmm... I THINK this'll work?'
									$subChildName = "$($objectName)>>$($arrayValue)";
									$facets += New-DynamicFacet -BaseFacet $compoundFacet -SqlInstanceName $sqlInstance -ObjectName $objectName -ChildName $instanceName -SubChildName $subChildName;
								}
							}
						}
					}
				}
			}
		}
		
#		Write-Host "-------------------------------------------------------------------------------------------------------------------------";
#		Write-Host "";
#		
#		Write-Host "Count of Facets: $($facets.Count)";
#		foreach ($facet in $facets) {
#			Write-Host "FACET: $($facet.Name):"
#			Write-Host "	FacetType: $($facet.FacetType)"
#			Write-Host "	CurrentKey: $($facet.CurrentKey)"
#			Write-Host "	CurrentKeyValue: $($facet.CurrentKeyValue)"
#			Write-Host "	CurrentObject: $($facet.CurrentObjectName)"
#			Write-Host "	CurrentSqlInstance: $($facet.CurrentSqlInstanceName)"
#			Write-Host "		Expect: $($facet.Expect) ";
#		}
#		return;
		
		# --------------------------------------------------------------------------------------
		# Validations
		# --------------------------------------------------------------------------------------	
		$validations = @();
		$surfaceProcessingResult.StartValidations();
		$validationsOutcome = [Proviso.Enums.ValidationsOutcome]::Completed;
		
		foreach ($facet in $facets) {
			$validationResult = New-Object Proviso.Processing.ValidationResult($facet, $processingGuid); 
			$validations += $validationResult;
			
			[ScriptBlock]$expectedBlock = $facet.Expect;
			if ($null -eq $expectedBlock) {
				throw "Proviso Framework Error. Expect block should be loaded - but is NOT.";	
			}
			
			$expectedResult = $null;
			$expectedException = $null;
			
			$PVContext.SetValidationState($facet);
			
			try {
				$expectedResult = & $expectedBlock;
			}
			catch {
				$expectedException = $_;
			}
						
			if ($expectedException) {
				$validationError = New-Object Proviso.Processing.ValidationError([Proviso.Enums.ValidationErrorType]::Expected, $expectedException);
				$validationResult.AddValidationError($validationError);
			}
			else {
				$PVContext.SetCurrentExpectValue($expectedResult);
				$validationResult.AddExpectedResult($expectedResult);
				
				[ScriptBlock]$testBlock = $facet.Test;
				
				$comparison = Compare-ExpectedWithActual -Expected $expectedResult -TestBlock $testBlock;
				
				$validationResult.AddComparisonResults(($comparison.ActualResult), ($comparison.Matched));
				
				if ($null -ne $comparison.ActualError) {
					$validationError = New-Object Proviso.Processing.ValidationError([Proviso.Enums.ValidationErrorType]::Actual, ($comparison.ActualError));
					$validationResult.AddValidationError($validationError);
				}
				
				if ($null -ne $comparison.ComparisonError) {
					$validationError = New-Object Proviso.Processing.ValidationError([Proviso.Enums.ValidationErrorType]::Compare, ($comparison.ComparisonError));
					$validationResult.AddValidationError($validationError);
				}
				
				if ($validationResult.Failed) {
					$validationsOutcome = [Proviso.Enums.ValidationsOutcome]::Failed; # i.e., exception/failure.
				}
			}
			
			$PVContext.ClearSurfaceState();
		}
		
		$surfaceProcessingResult.EndValidations($validationsOutcome, $validations);
		
		# --------------------------------------------------------------------------------------
		# Rebase
		# --------------------------------------------------------------------------------------
		if ($ExecuteRebase) {
			
			$surfaceProcessingResult.StartRebase();
			
			if ($surfaceProcessingResult.ValidationsFailed) {
				$PVContext.WriteLog("FATAL: Rebase Failure - One or more Validations threw an exception (and could not be properly evaluated). Rebase Processing can NOT continue. Terminating.", "Critical");
				$surfaceProcessingResult.EndRebase([Proviso.Enums.RebaseOutcome]::Failure, $null);
				
				$surfaceProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentSurface();
				
				return;
			}
			
			[ScriptBlock]$rebaseBlock = $surface.Rebase.RebaseBlock;
			$rebaseResult = New-Object Proviso.Processing.RebaseResult(($surface.Rebase), $processingGuid);
			$rebaseOutcome = [Proviso.Enums.RebaseOutcome]::Success;
			
			try {
				& $rebaseBlock;
				
				$rebaseResult.SetSuccess();
			}
			catch {
				$rebaseResult.SetFailure($_);
				$rebaseOutcome = [Proviso.Enums.RebaseOutcome]::Failure;
			}
			
			$surfaceProcessingResult.EndRebase($rebaseOutcome, $rebaseResult);
			
			if($surfaceProcessingResult.RebaseFailed){
				$surfaceProcessingResult.SetProcessingFailed();
				$PVContext.WriteLog("FATAL: Rebase Failure: [$($rebaseResult.RebaseError)].  Configuration Processing can NOT continue. Terminating.", "Critical");
				
				$surfaceProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentSurface();
				
				return;
			}
		}
	
		# --------------------------------------------------------------------------------------
		# Configuration
		# --------------------------------------------------------------------------------------		
		if ("Configure" -eq $Operation) {
			
			$surfaceProcessingResult.StartConfigurations();
			
			if ($surfaceProcessingResult.ValidationsFailed){
				# vNEXT: might... strangely, also, make sense to let some comparisons/failures be NON-FATAL (but, assume/default to fatal... in all cases)
				$PVContext.WriteLog("FATAL: Configurations Failure - One or more Validations threw an exception (and could not be properly evaluated). Configuration Processing can NOT continue. Terminating.", "Critical");
				$surfaceProcessingResult.EndConfigurations([Proviso.Enums.ConfigurationsOutcome]::Failed, $null);
				
				$surfaceProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentSurface();
				
				return;
			}
			
			$configurations = @();
			$configurationsOutcome = [Proviso.Enums.ConfigurationsOutcome]::Completed;
			
			[string[]]$configuredByFacetsCalledThroughDeferredOperations = @();
			
			foreach($validation in $surfaceProcessingResult.ValidationResults) {
							
				$configurationResult = New-Object Proviso.Processing.ConfigurationResult($validation);
				$configurations += $configurationResult;
				
				if ($validation.Matched) {
					$configurationResult.SetBypassed();
					$PVContext.WriteLog("Bypassing configuration of [$($validation.Name)] - Expected: [$($validation.Expected)] and Actual: [$($validation.Actual)] values already matched.", "Debug");
				}
				else {
					$PVContext.SetConfigurationState($validation);
					
					try {
						[ScriptBlock]$configureBlock = $null;
						if ($validation.ParentFacet.UsesBuild) {
							$configureBlock = $surface.Build.BuildBlock;
						}
						else {
							$configureBlock = $validation.Configure;
						}
						
						& $configureBlock;
					}
					catch {
						$configurationsOutcome = [Proviso.Enums.ConfigurationsOutcome]::Failed;
						$configurationError = New-Object Proviso.Processing.ConfigurationError($_);
						$configurationResult.AddConfigurationError($configurationError);
					}
					
					$PVContext.ClearSurfaceState();
				}
			}
			
			if ($surface.UsesBuild) {
				# NOTE: there's no 'state' within a Deploy operation... (e.g., Configure operations use .SetConfigurationState(), validations use .SetValidationState(), but ... there's NO state here.)
				try {
					[ScriptBlock]$deployBlock = $surface.Deploy.DeployBlock;
					
					& $deployBlock;
				}
				catch {
					# TODO: MIGHT want to create a specific type of error: Deploy Error... 
					$configurationsOutcome = [Proviso.Enums.ConfigurationsOutcome]::Failed;
					$configurationError = New-Object Proviso.Processing.ConfigurationError($_);
					$configurationResult.AddConfigurationError($configurationError);
				}
			}
			
			# Now that we're done running configuration operations, time to execute Re-Compare operations:
			$targets = $configurations | Where-Object { ($_.ConfigurationBypassed -eq $false) -and ($_.ConfigurationFailed -eq $false);	};
			foreach ($configurationResult in $targets) {
				$PVContext.SetConfigurationState($configurationResult.Validation);
				
				try {
					[ScriptBlock]$testBlock = $configurationResult.Validation.Test;
					
					$reComparison = Compare-ExpectedWithActual -Expected ($configurationResult.Validation.Expected) -TestBlock $testBlock;
					
					$configurationResult.SetRecompareValues(($configurationResult.Validation.Expected), ($reComparison.ActualResult), ($reComparison.Matched), ($reComparison.ActualError), ($reComparison.ComparisonError));
				}
				catch {
					$configurationError = New-Object Proviso.Processing.ConfigurationError($_);
					$configurationResult.AddConfigurationError($configurationError);
				}
				
				if ($configurationResult.RecompareFailed) {
					$configurationsOutcome = [Proviso.Enums.ConfigurationsOutcome]::RecompareFailed;
				}
				
				$PVContext.ClearSurfaceState();
			}
			
			$surfaceProcessingResult.EndConfigurations($configurationsOutcome, $configurations);
		}
	}
	
	end {
		$surfaceProcessingResult.SetProcessingComplete();
		$PVContext.CloseCurrentSurface();
		
		# Check for Reboot/Restart requirements when in a Runbook: 
		if ($null -ne $PVContext.CurrentRunbook) {
			$currentRunbook = $PVContext.CurrentRunbook;
			if ($PVContext.SqlRestartRequired) {
				if ($PVContext.CurrentRunbookAllowsSqlRestart) {
					Write-Host "!!!!!!!!!!!!!!!!!!! SIMULATED SQL RESTART --- HAPPENING RIGHT NOW !!!!!!!!!!!!!!!!!!!";
				}
			}
			
			if ($PVContext.RebootRequired) {
				if ($PVContext.CurrentRunbookAllowsReboot) {
					if ($currentRunbook.DeferRebootUntilRunbookEnd) {
						$PVContext.WriteLog("Reboot Required and Allowed - but Runboook [$($currentRunbook.Name)] directs that reboot be deferred until end of Runbook Processing.", "Verbose");
					}
					else {
						$wait = $currentRunbook.WaitSecondsBeforeReboot;
						$targetOperation = "$($PVContext.CurrentRunbookVerb)-$($currentRunbook.Name)"
						Restart-Server -WaitSeconds $wait -RestartRunbookTarget $targetOperation;
					}
				}
				else {
					$PVContext.WriteLog("Reboot Required for Runbook [$($currentRunbook.Name)] against Surface: [$($surface.Name)] - but Runbook Processing does NOT allow reboots.", "Important");
				}
			}
		}
		else {
			# i.e., we're NOT in a runbook... 
			if ($PVContext.RebootRequired) {
				# TODO: allow storage of N rebootReasons + tweak .RebootReason to serialize/output all reasons needed for reboot. 
				# 		use case for the above: assume that Surface 3 of 5 requires a reboot, we'd store WHY (and display (here) why...). But what if Surface 5/5 ALSO requires a reboot? 
				# 			by storing > 1 ... we keep/output ALL reasons for why a reboot is required.
				$PVContext.WriteLog("Surface Configuration Complete. REBOOT REQUIRED. $($PVContext.RebootReason)", "IMPORTANT");
			}
			
			if ($PVContext.SqlRestartRequired) {
				$PVContext.WriteLog("SQL RESTART REQUIRED. $($PVContext.SqlRestartReason)", "IMPORTANT");
			}
		}
	}
}