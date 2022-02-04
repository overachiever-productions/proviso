﻿Set-StrictMode -Version 1.0;

Surface AdminDbBackups {
	Assertions {
		Assert-SqlServerIsInstalled;
		Assert-AdminDbInstalled;
	}
	
	Aspect -Scope "AdminDb.*" {
		Facet "BackupsEnabled" -ExpectChildKeyValue "BackupJobs.Enabled" {
			Test {
				# this one's a bit complex. IF no jobs exist, then $false. 
				# otherwise, if all jobs exist: $true. 
				# BUT, if only some jobs exist, report on which ones... 
				
				$instanceName = $PVContext.CurrentKeyValue;
				$jobsPrefix = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.JobsNamePrefix");
				
				$systemStart = Get-AgentJobStartTime -SqlServerAgentJob "$($jobsPrefix)SYSTEM - Full" -SqlServerInstanceName $instanceName;
				$fullStart = Get-AgentJobStartTime -SqlServerAgentJob "$($jobsPrefix)USER - Full" -SqlServerInstanceName $instanceName;
				$logsStart = Get-AgentJobStartTime -SqlServerAgentJob "$($jobsPrefix)USER - Log" -SqlServerInstanceName $instanceName;
				
				$system = $full = $log = $false;
				if ($systemStart -notlike "<*") {
					$system = $true;
				}
				if ($fullStart -notlike "<*") {
					$full = $true;
				}
				if ($logsStart -notlike "<*") {
					$log = $true;
				}
				
				# feels tedious... 
				if (($system -eq $false) -and ($full -eq $false) -and ($log -eq $false)) {
					return $false;
				}
				
				if ($system -and $full -and $log) {
					return $true;
				}
				
				if ($full -and $log) {
					return "<USER_ONLY>";
				}
				elseif ($system) {
					return "<SYSTEM_ONLY";
				}
				
				return "<MIXED>";
				
			}
			Configure {
				$instanceName = $PVContext.CurrentKeyValue;
				
				$userDbTargets = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.UserDatabasesToBackup");
				$userDbExclusions = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.UserDbsToExclude");
				$certName = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.CertificateName");
				$backupsDir = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.BackupDirectory");
				$copyTo = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.CopyToDirectory");
				$systemRetention = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.SystemBackupRetention");
				$copyToSystemRetention = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.CopyToSystemBackupRetention");
				$userRetention = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.UserBackupRetention");
				$copyToUserRetention = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.CopyToUserBackupRetention");
				$logRetention = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.LogBackupRetention");
				$copyToLogRetention = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.CopyToLogBackupRetention");
				$allowForSecondaries = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.AllowForSecondaries");
				$fullSystemStart = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.SystemBackupsStart");
				$fullUserStart = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.UserBackupsStart");
				$diffsStart = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.DiffBackupsStart");
				$diffsEvery = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.DiffBackupsEvery");
				$logsStart = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.LogBackupsStart");
				$logsEvery = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.LogBackupsEvery");
				$backupsTimeZone = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.TimeZoneForUtcOffset");
				$backupsPrefix = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.JobsNamePrefix");
				$backupsCategory = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.JobsCategoryName");
				$backupsOperator = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.Operator");
				$backupsProfile = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.Profile");
				
				$secondaries = "0";
				if ($allowForSecondaries) {
					$secondaries = "1";
				}
				
				Invoke-SqlCmd -ServerInstance (Get-ConnectionInstance $instanceName) -Query "EXEC admindb.dbo.[create_backup_jobs]
					@UserDBTargets = N'$userDbTargets',
					@UserDBExclusions = N'$userDbExclusions',
					@EncryptionCertName = N'$certName',
					@BackupsDirectory = N'$backupsDir',
					@CopyToBackupDirectory = N'$copyTo',
					@SystemBackupRetention = N'$systemRetention',
					@CopyToSystemBackupRetention = N'$copyToSystemRetention',
					@UserFullBackupRetention = N'$userRetention',
					@CopyToUserFullBackupRetention = N'$copyToUserRetention',
					@LogBackupRetention = N'$logRetention',
					@CopyToLogBackupRetention = N'$copyToLogRetention',
					@AllowForSecondaryServers = $secondaries,
					@FullSystemBackupsStartTime = N'$fullSystemStart',
					@FullUserBackupsStartTime = N'$fullUserStart',
					@DiffBackupsStartTime = N'$diffsStart',
					@DiffBackupsRunEvery = N'$diffsEvery',
					@LogBackupsStartTime = N'$logsStart',
					@LogBackupsRunEvery = N'$logsEvery',
					@TimeZoneForUtcOffset = N'$backupsTimeZone',
					@JobsNamePrefix = N'$backupsPrefix',
					@JobsCategoryName = N'$backupsCategory',
					@JobOperatorToAlertOnErrors = N'$backupsOperator',
					@ProfileToUseForAlerts = N'$backupsProfile',
					@OverWriteExistingJobs = 1; ";
				
			}
		}
		
		Facet "UserTargets" -ExpectChildKeyValue "BackupJobs.UserDatabasesToBackup" -UsesBuild {
			Test {
				$instanceName = $PVContext.CurrentKeyValue;
				$jobsPrefix = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.JobsNamePrefix");
				
				$fullBackupsJobName = "$($jobsPrefix)USER - Full";
				
				$jobStepBody = Get-AgentJobStepBody -SqlServerAgentJob $fullBackupsJobName -JobStepName "FULL Backup of USER Databases" -SqlServerInstanceName $instanceName;
				if ($jobStepBody -like "<*") {
					return $jobStepBody;
				}
				
				$regex = New-Object System.Text.RegularExpressions.Regex("@DatabasesToBackup = N'(?<targets>[^']+)", [System.Text.RegularExpressions.RegexOptions]::Multiline);
				$matches = $regex.Match($jobStepBody);
				if ($matches) {
					$targets = $matches.Groups[1].Value;
					
					return $targets;
				}
			}
		}
		
		Facet "TLogFrequency" -ExpectChildKeyValue "BackupJobs.LogBackupsEvery" -UsesBuild {
			Test {
				$instanceName = $PVContext.CurrentKeyValue;
				$jobsPrefix = $PVConfig.GetValue("AdminDb.$instanceName.BackupJobs.JobsNamePrefix");
				
				$tLogJobName = "$($jobsPrefix)USER - Log";
				
				return Get-AgentJobRecurringMinutes -SqlServerAgentJob $tLogJobName -SqlServerInstanceName $instanceName;
			}
		}
		
		Build {
			
			
		}
		
		Deploy {
			
		}
	}
}