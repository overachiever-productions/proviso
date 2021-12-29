﻿Set-StrictMode -Version 1.0;

<#

# intermediate dev/testing against target VMs:
	#Register-PSRepository -Name Pro2 -SourceLocation "\\storage\lab\proviso\repo2" -InstallationPolicy Trusted;
Install-Module -Name Proviso -Repository Pro2 -Force;
Import-Module -Name Proviso -Force -DisableNameChecking;
Assign -ProvisoRoot "\\storage\Lab\proviso\";
With -CurrentHost | Do-Something;


	Import-Module -Name "D:\Dropbox\Repositories\proviso\" -DisableNameChecking -Force;
	#Assign -ProvisoRoot "\\storage\Lab\proviso\";

	#With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Configure-ServerName;
	#With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Validate-NetworkAdapters;

	#With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Validate-FirewallRules;
	#With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Validate-RequiredPackages;

	#With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Validate-LocalAdmins;
	#With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Validate-TestingFacet;
	 With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Configure-TestingFacet;
	#With "\\storage\lab\proviso\definitions\servers\PRO\PRO-197.psd1" | Validate-DataCollectorSets;

	Summarize -All; # -IncludeAllValidations; # -IncludeAssertions;

#>

function Process-Facet {
	
	param (
		[Parameter(Mandatory)]
		[string]$FacetName,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
		[PSCustomObject]$Config,
		[Switch]$ExecuteRebase = $false,
		[Switch]$Force = $false,
		[Switch]$ExecuteConfiguration = $false
	);
	
	begin {
		Validate-MethodUsage -MethodName "Process-Facet";
		
		$facet = $ProvisoFacetsCatalog.GetFacet($FacetName);
		if ($null -eq $facet) {
			throw "Invalid Facet-Name. [$FacetName] does not exist or has not yet been loaded. If this is a custom Facet, verify that [Import-Facet] has been executed.";
		}
		
		if ($ExecuteRebase) {
			if (-not ($Force)) {
				throw "Invalid -ExecuteRebase inputs. Because Rebase CAN be detrimental, it MUST be accompanied with the -Force [switch] as well.";
			}
		}
		
		$facetProcessingResult = New-Object Proviso.Processing.FacetProcessingResult($facet, $ExecuteConfiguration);
		$PVContext.SetCurrentFacet($facet, $ExecuteRebase, $ExecuteConfiguration, $facetProcessingResult);
	}
	
	process {
		# --------------------------------------------------------------------------------------
		# Setup	
		# --------------------------------------------------------------------------------------
		if ($facet.Setup.SetupBlock) {
			try {
				[ScriptBlock]$setupBlock = $facet.Setup.SetupBlock;
				
				& $setupBlock;
			}
			catch{
				$PVContext.WriteLog("FATAL: Facet.Setup FAILED for Facet [$($facet.Name)]. Error Detail: $($_)", "Critical");
			}
		}
		
		# --------------------------------------------------------------------------------------
		# Assertions	
		# --------------------------------------------------------------------------------------
		$assertionsFailed = $false;
		if ($facet.Assertions.Count -gt 0) {
			
			$facetProcessingResult.StartAssertions();
			$results = @();
			
			$assertionsOutcomes = [Proviso.Enums.AssertionsOutcome]::AllPassed;
			foreach ($assert in $facet.Assertions) {
				$assertionResult = New-Object Proviso.Processing.AssertionResult($assert);
				$results += $assertionResult;
				
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
				$facetProcessingResult.EndAssertions([Proviso.Enums.AssertionsOutcome]::HardFailure, $results);
				
				$facetProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentFacet();
				
				return; 
			}
			else {
				$facetProcessingResult.EndAssertions($assertionsOutcomes, $results);
			}
		}
		
		# --------------------------------------------------------------------------------------
		# Definitions / Testing
		# --------------------------------------------------------------------------------------	
		$validations = @();
		$facetProcessingResult.StartValidations();
		$validationsOutcome = [Proviso.Enums.ValidationsOutcome]::Completed;
		
		$definitions = $facet.GetSimpleDefinitions();
		$valueDefs = $facet.GetBaseValueDefinitions();
		$groupDefs = $facet.GetBaseGroupDefinitions();
		
		if ($valueDefs) {
			$expandedDefs = @();
			
			foreach ($definition in $valueDefs) {
				
				$values = Get-ProvisoConfigValueByKey -Config $Config -Key ($definition.ParentKey);
				if ($values.Count -lt 1) {
					$PVContext.WriteLog("NOTE: No Config Array-Values were found at key [$($definition.ParentKey)] for Definition [$($definition.Parent.Name)::$($definition.Description)].", "Important");
				}
				
				foreach ($value in $values) {
					$newDescription = "$($definition.Description):$($value)";
					
					$expandedValueDefinition = New-Object Proviso.Models.Definition(($definition.Parent), $newDescription, [Proviso.Enums.DefinitionType]::Value);
 					if ($definition.CurrentValueKeyAsExpect) {
						$script = "return '$value';";
						$expectedBlock = [scriptblock]::Create($script);
						
						$expandedValueDefinition.AddExpect($expectedBlock);
					}
					else {
						$expandedValueDefinition.AddExpect(($definition.Expectation));
					}
					
					$expandedValueDefinition.AddTest(($definition.Test));
					$expandedValueDefinition.AddConfigure(($definition.Configure));
					$expandedValueDefinition.AddCurrentKeyValue($value);
					
					$expandedDefs += $expandedValueDefinition;
				}
			}
			
			$definitions += $expandedDefs;
		}
		
		if ($groupDefs) {
			$expandedDefs = @();
			
			foreach ($definition in $groupDefs) {
				
				[string]$trimmedKey = ($definition.ParentKey) -replace ".\*", "";
				
				$groupNames = Get-ProvisoConfigGroupNames -Config $Config -GroupKey $trimmedKey -OrderByKey:$($definition.OrderByChildKey);
				if ($groupNames.Count -lt 1) {
					$PVContext.WriteLog("NOTE: No Configuration Group-Values were found at key [$($definition.ParentKey)] for Definition [$($definition.Parent.Name)::$($definition.Description)].", "Important");
				}
				
				foreach ($groupName in $groupNames) {
					
					$newDescription = "$($definition.Description):$($groupName)";
					
					$expandedGroupDefinition = New-Object Proviso.Models.Definition(($definition.Parent), $newDescription, [Proviso.Enums.DefinitionType]::Group);
					
					if (-not ($definition.Expectation)) {
						$fullKey = "$($trimmedKey).$($groupName).$($definition.ChildKey)";
						$actualValue = Get-ProvisoConfigValueByKey -Config $Config -Key $fullKey;
						$script = "return '$actualValue';";
						$expectedBlock = [scriptblock]::Create($script);
						
						$expandedGroupDefinition.AddExpect($expectedBlock);
						$expandedGroupDefinition.AddCurrentKeyValue($actualValue);
					}
					else {
						$expandedGroupDefinition.AddExpect(($definition.Expectation));
					}
					
					$expandedGroupDefinition.AddTest(($definition.Test));
					$expandedGroupDefinition.AddConfigure(($definition.Configure));
					$expandedGroupDefinition.AddCurrentKeyGroup($groupName);
					
					$expandedDefs += $expandedGroupDefinition;
				}
			}
			
			$definitions += $expandedDefs;
		}
		
		foreach ($definition in $definitions) {
			
			$validationResult = New-Object Proviso.Processing.ValidationResult($definition); 
			$validations += $validationResult;			
			
			[ScriptBlock]$expectedBlock = $definition.Expectation;
			if (($null -eq $expectedBlock) -and ($null -ne $definition.Key)) { 	# dynamically CREATE a script-block ... that spits out the config key: 
				$script = "return `$Config.GetValue('$($definition.Key)');";
				$expectedBlock = [scriptblock]::Create($script);
			}
			
			$expectedResult = $null;
			$expectedException = $null;
			
			if ($definition.DefinitionType -eq [Proviso.Enums.DefinitionType]::Value) {
				$PVContext.SetCurrentKeyValue($definition.CurrentKeyValueForValueDefinitions);
			}
			
			if ($definition.DefinitionType -eq [Proviso.Enums.DefinitionType]::Group) {
				# REFACTOR: this needs to be refactored. I don't MIND using the same func to display 'current value'... but, the name needs to reflect that this is more generic (than the hyper-specific name that was initially created here for VALUEDEF stuff);
				$PVContext.SetCurrentKeyValue($definition.CurrentKeyValueForValueDefinitions);
				$PVContext.SetCurrentKeyGroup($definition.CurrentKeyGroupForGroupDefinitions);
			}
			
			try {
				$expectedResult = & $expectedBlock;
			}
			catch {
				$expectedException = $_;
			}
						
			if ($null -ne $expectedException) {
				$validationError = New-Object Proviso.Processing.ValidationError([Proviso.Enums.ValidationErrorType]::Expected, $expectedException);
				$validationResult.AddValidationError($validationError);
			}
			else {
				$PVContext.SetCurrentExpectValue($expectedResult);
				
				$validationResult.AddExpectedResult($expectedResult);
				[ScriptBlock]$testBlock = $definition.Test;
				$comparison = Compare-ExpectedWithActual -Expected $expectedResult -TestBlock $testBlock;
				
				$validationResult.AddComparisonResults(($comparison.ActualResult), ($comparison.Matched))
				
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
				
				$PVContext.RemoveCurrentExpectValue();
			}
			
			$PVContext.ClearCurrentKeyValue();
		}
		
		$facetProcessingResult.EndValidations($validationsOutcome, $validations);
		
		# --------------------------------------------------------------------------------------
		# Rebase
		# --------------------------------------------------------------------------------------
		if ($ExecuteRebase) {
			
			$facetProcessingResult.StartRebase();
			
			if ($facetProcessingResult.ValidationsFailed) {
				$PVContext.WriteLog("FATAL: Rebase Failure - One or more Validations threw an exception (and could not be properly evaluated). Rebase Processing can NOT continue. Terminating.", "Critical");
				$facetProcessingResult.EndRebase([Proviso.Enums.RebaseOutcome]::Failure, $null);
				
				$facetProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentFacet();
				
				return;
			}
			
			[ScriptBlock]$rebaseBlock = $facet.Rebase.RebaseBlock;
			$rebaseResult = New-Object Proviso.Processing.RebaseResult(($facet.Rebase));
			$rebaseOutcome = [Proviso.Enums.RebaseOutcome]::Success;
			
			try {
				& $rebaseBlock;
				
				$rebaseResult.SetSuccess();
			}
			catch {
				$rebaseResult.SetFailure($_);
				$rebaseOutcome = [Proviso.Enums.RebaseOutcome]::Failure;
			}
			
			$facetProcessingResult.EndRebase($rebaseOutcome, $rebaseResult);
			
			if($facetProcessingResult.RebaseFailed){
				$facetProcessingResult.SetProcessingFailed();
				$PVContext.WriteLog("FATAL: Rebase Failure: [$($rebaseResult.RebaseError)].  Configuration Processing can NOT continue. Terminating.", "Critical");
				
				$facetProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentFacet();
				
				return;
			}
		}
	
		# --------------------------------------------------------------------------------------
		# Configuration
		# --------------------------------------------------------------------------------------		
		if ($ExecuteConfiguration) {
			
			$facetProcessingResult.StartConfigurations();
			
			if ($facetProcessingResult.ValidationsFailed){
				# vNEXT: might... strangely, also, make sense to let some comparisons/failures be NON-FATAL (but, assume/default to fatal... in all cases)
				$PVContext.WriteLog("FATAL: Configurations Failure - One or more Validations threw an exception (and could not be properly evaluated). Configuration Processing can NOT continue. Terminating.", "Critical");
				$facetProcessingResult.EndConfigurations([Proviso.Enums.ConfigurationsOutcome]::Failed, $null);
				
				$facetProcessingResult.SetProcessingComplete();
				$PVContext.CloseCurrentFacet();
				
				return;
			}
			
			$configurations = @();
			$configurationsOutcome = [Proviso.Enums.ConfigurationsOutcome]::Completed;
			
			foreach($validation in $facetProcessingResult.ValidationResults) {
				
				$configurationResult = New-Object Proviso.Processing.ConfigurationResult($validation);
				$configurations += $configurationResult;
				
				if ($validation.Matched) {
					$configurationResult.SetBypassed();
					$PVContext.WriteLog("Bypassing configuration of [$($validation.Description)] - Expected and Actual values already matched.", "Debug");
				}
				else {
					if ($validation.ParentDefinition.DefinitionType -eq [Proviso.Enums.DefinitionType]::Value) {
						$PVContext.SetCurrentKeyValue($validation.ParentDefinition.CurrentKeyValueForValueDefinitions);
					}
					
					try {
						$PVContext.SetCurrentExpectValue($validation.Expected);
						$PVContext.SetCurrentActualValue($validation.Actual);
						
						[ScriptBlock]$configureBlock = $validation.Configure;
						
						& $configureBlock;
					}
					catch {
						$configurationsOutcome = [Proviso.Enums.ConfigurationsOutcome]::Failed;
						$configurationError = New-Object Proviso.Processing.ConfigurationError($_, $false);
						$configurationResult.AddConfigurationError($configurationError);
					}
					
					# Recomparisons:
					$PVContext.SetRecompareActive();
					if (-not ($configurationResult.ConfigurationFailed)) {
						
						try {
							[ScriptBlock]$testBlock = $validation.Test;
							
							$reComparison = Compare-ExpectedWithActual -Expected $validation.Expected -TestBlock $testBlock;
							
							$configurationResult.SetRecompareValues(($validation.Expected), ($reComparison.ActualResult), ($reComparison.Matched), ($reComparison.ActualError), ($reComparison.ComparisonError));
						}
						catch {
							$configurationError = New-Object Proviso.Processing.ConfigurationError($_, $true);
							$configurationResult.AddConfigurationError($configurationError);
						}
						
						if ($configurationResult.RecompareFailed) {
							$configurationsOutcome = [Proviso.Enums.ConfigurationsOutcome]::RecompareFailed;
						}
					}
					
					$PVContext.RemoveCurrentExpectValue();
					$PVContext.RemoveCurrentActualValue();
					$PVContext.SetRecompareInactive();
					
					$PVContext.ClearCurrentKeyValue();
				}
			}
			
			$facetProcessingResult.EndConfigurations($configurationsOutcome, $configurations);
		}
	}
	
	end {
		$facetProcessingResult.SetProcessingComplete();
		$PVContext.CloseCurrentFacet();
		
		if ($PVContext.RebootRequired) {
			$message = "REBOOT REQUIRED. $($PVContext.RebootReason)";
			
			$PVContext.WriteLog($message, "CRITICAL");
		}
	}
}