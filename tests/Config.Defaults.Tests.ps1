Set-StrictMode -Version 1.0;

BeforeAll {
	$root = Split-Path -Parent $PSCommandPath.Replace("\tests", "");
	
	. "$root\internal\dsl\ProvisoConfig.ps1";
	. "$root\internal\dsl\ProvisoConfig-Defaults.ps1";
	$script:be8c742fDefaultConfigData = $script:ProvisoConfigDefaults;
}

Describe "Extended Events Defaults" {
	Context "Per Instance Defaults" {
		It "Sets DisableTelemetry to true by Default" {
			# Sadly a BIT too easy for this one to ACCIDENTALLY get whack-a-mole'd into being $false - so, this test helps 'seal this in place':
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.MSSQLSERVER.DisableTelemetry" | Should -Be $true;
		}
		
		It "Sets DefaultDirectory and BlockedProcess Thresholds" {
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.X3.DefaultXelDirectory" | Should -Be "D:\Traces";
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.SALES11.BlockedProcessThreshold" | Should -Be 0;
		}
	}
	
	Context "Session Name Tests" {
		It "Defines SessionName as Parent Key by Default" {
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.MSSQLSERVER.BlockedProcesses.SessionName" | Should -Be "BlockedProcesses";
			
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.MSSQLSERVER.PigglyWiggly.SessionName" | Should -Be "PigglyWiggly";
		}
	}
	
	Context "Xe Log File Tests" {
		It "Defines a Default for Xel File Counts" {
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.MSSQLSERVER.BlockedProcesses.XelFileCount" | Should -Be 6;
		}
		
		It "Defines a Default for Xel File Sizes" {
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.MSSQLSERVER.BlockedProcesses.XelFileSizeMb" | Should -Be 100;
		}
		
		It "Defines a Default path for Xel Files" {
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.MSSQLSERVER.BlockedProcesses.XelFilePath" | Should -Be "D:\Traces";
		}
	}
	
	Context "Dynamic Definition File Tests" {
		It "Uses Conventions for XeSession Definition file if Not Provided" {
			Get-ProvisoConfigDefaultValue -Key "ExtendedEvents.SQL18.BlockedProcesses.DefinitionFile" | Should -Be "BlockedProcesses.sql";
		}
	}
}

Describe "ClusterConfiguration Defaults" {
	Context "Scalar ClusterConfiguration Defaults" {
		It "Defines NONE as the ClusterType Default" {
			Get-ProvisoConfigDefaultValue -Key "ClusterConfiguration.ClusterType" | Should -Be "NONE";
		}
		
		It "Defines WARN as EvictionBehavior Default" {
			Get-ProvisoConfigDefaultValue -Key "ClusterConfiguration.EvictionBehavior" | Should -Be "WARN";
		}
		
		It "Prevents Default Value for PrimaryNode Definition" {
			{ Get-ProvisoConfigDefaultValue -Key "ClusterConfiguration.PrimaryNode" } | Should -Throw;
		}
		
		It "Prevents Default Value for ClusterName Definition" {
			{ Get-ProvisoConfigDefaultValue -Key "ClusterConfiguration.ClusterName" } | Should -Throw;
		}
	}
	
	Context "Array ClusterConfiguration Defaults" {
		It "Specified Empty as ClusterNodes Default" {
			Get-ProvisoConfigDefaultValue -Key "ClusterConfiguration.ClusterNodes" | Should -Be @();
		}
		
		It "Specified Empty as ClusterIPs Default" {
			Get-ProvisoConfigDefaultValue -Key "ClusterConfiguration.ClusterIPs" | Should -Be @();
		}
		
		It "Specified Empty as ClusterDisks Default" {
			Get-ProvisoConfigDefaultValue -Key "ClusterConfiguration.ClusterDisks" | Should -Be @();
		}
		
	}
}