<#
	.SYNOPSIS
	Automatically adds (or updates) Azure SQL Server firewall IP rules to contain those of an Azure App Service's outbound IP addresses.

	.DESCRIPTION
	This script looks up the specified Azure App Service's outbound IP address list and automatically updates the specified Azure SQL Server firewall IP rules to contain these entries.
	The entries created match the following convention: App-<AppServicePlan>-<AppService>-##
	For example: App-MyASP-MyWebApp-01

	.PARAMETER SqlServerName
	Specifies the name of the Azure SQL Server to modify.

	.PARAMETER SqlResourceGroup
	Specifies the resource group container name the Azure SQL Server.

	.PARAMETER AppName
	Specifies the name of the Azure App Service to query outbound IP addresses for.

	.PARAMETER AppResourceGroup
	Specifies the resource group container name the Azure App Service.
	
	.PARAMETER RemoveConflicts
	Optional - Removes any existing, but conflicting rule entries instead of deprecating (by re-creating under a new name).

	.INPUTS
	None. You cannot pipe objects to Add-AzSQL-AppServicePlan-IPs.

	.OUTPUTS
	None. This script logs to the Host console.

	.EXAMPLE
	PS> .\Add-AzSQL-AppServicePlan-IPs.ps1 -SqlServerName "SomeSqlServer" -SqlResourceGroup "SomeResourceGroup" -AppName "AppSvcName" -AppResourceGroup "AppSvcResourceGroup"

	.EXAMPLE
	PS> .\Add-AzSQL-AppServicePlan-IPs.ps1 -SqlServerName "SomeSqlServer" -SqlResourceGroup "SomeResourceGroup" -AppName "AppSvcName" -AppResourceGroup "AppSvcResourceGroup" -RemoveConflicts

	.LINK
	Online version: https://github.com/dliktorius/azure-powershell-scripts

#>
<#
	MIT License

	Copyright (c) 2021 Darius Liktorius

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
#>

param(
	[Parameter(mandatory=$true)]
	[string] $SqlServerName,
	[Parameter(mandatory=$true)]
	[string] $SqlResourceGroup,
	[Parameter(mandatory=$true)]
	[string] $AppName,
	[Parameter(mandatory=$true)]
	[string] $AppResourceGroup,
	[Parameter(mandatory=$false)]
	[switch] $RemoveConflicts
)

# Array to hold rules to add
$rulesToAdd = @()

# Array to hold rules to remove
$rulesToRemove = @()

# Array to hold rules to keep but rename due to conflicts
$rulesToDeprecate = @()

Write-Host "Getting Firewall Rules from Server '$SqlServerName' in Resource Group '$SqlResourceGroup' ..."
$rules = Get-AzSqlServerFirewallRule -ResourceGroupName $SqlResourceGroup -ServerName $SqlServerName -ErrorAction Stop

Write-Host "Getting App Service '$AppName' in Resource Group '$AppResourceGroup' ..."
$app = Get-AzResource -ResourceGroup $AppResourceGroup -ResourceType Microsoft.Web/sites -ResourceName $AppName -ErrorAction Stop
$AppName = $app.Name

Write-Host "Getting App Service Plan for App Service ..."
$serverFarmName = (Get-AzResource -Id $app.Properties.serverFarmId -ErrorAction Stop).Properties.Name

Write-Host "App Service Plan Located: $serverFarmName"

$appOutboundIPs = $app.Properties.possibleOutboundIpAddresses
$appOutboundIPs = $appOutboundIPs.Split(',')

Write-Host "Found [$($appOutboundIPs.Count)] Possible Outbound IP(s):"

ForEach ($ip in $appOutboundIPs) { Write-Host "`t$ip" -ForegroundColor Gray }

# Loop through all 4 IP addresses of the web app
Foreach ($ip in $appOutboundIPs)
{
	$i++
	$addIP = $true
	
	$newRuleName = "App-$serverFarmName-$AppName-{0:d2}" -f $i
	
	$existingRules = ($rules | Where { ($_.FirewallRuleName -eq $newRuleName) -or ($_.StartIpAddress -eq $ip) })
	
	If ($existingRules) {
		
		ForEach ($rule in $existingRules) {
			
			if ($rule.FirewallRuleName -ne $newRuleName) {
			
				# Existing rule is present, but incorrectly named. Add to rules to remove
				Write-Host "Redundant rule '$($rule.FirewallRuleName)' named incorrectly for IP: $ip" -ForegroundColor Yellow
				$rulesToRemove += $rule
				
			} elseif ($rule.StartIpAddress -ne $ip -and $rule.EndIpAddress -ne $ip) {
				
				# Existing rule with this name exists, but for a different IP. Add to rules to deprecate (re-create under a new name)
				Write-Host "Conflicting rule '$($rule.FirewallRuleName)' exists for different IP: $($rule.StartIpAddress) -> $($rule.EndIpAddress)" -ForegroundColor Yellow
				$rulesToDeprecate += $rule

			} else {
				
				# Existing rule for IP is present and correctly named, skip to the next IP
				Write-Host "Existing rule found '$($rule.FirewallRuleName)' for IP: $ip" -ForegroundColor Green
				$addIP = $false
			}
		}		
	}
	
	if ($addIP) {
		$rulesToAdd += @{ 
			'FirewallRuleName' = $newRuleName;
			'StartIpAddress' = $ip;
			'EndIpAddress' = $ip
		}
	}
}

Write-Host ""

if ($rulesToDeprecate.Count -gt 0) {
	
	if ($RemoveConflicts) {
		Write-Host "Found [$($rulesToDeprecate.Count)] conflicting rule(s) to remove (-RemoveConflicts parameter used) ..."
	} else {
		Write-Host "Found [$($rulesToDeprecate.Count)] conflicting rule(s) to deprecate (re-create under a new name) ..."
	}
	
	Foreach ($rule in $rulesToDeprecate)
	{
		if ($RemoveConflicts) {
			# Remove conflicts
			Write-Host "- Removing conflicting rule '$($rule.FirewallRuleName)' ..." -ForegroundColor Yellow
			$result = Remove-AzSqlServerFirewallRule -FirewallRuleName $rule.FirewallRuleName -ServerName $SqlServerName -ResourceGroupName $SqlResourceGroup -Force -ErrorAction Stop
			Write-Host "  Successfully removed rule '$($rule.FirewallRuleName)'" -ForegroundColor Cyan
		} else {			
			# Deprecate conflicts
			$prefix = (Get-Date).ToString("yyMMddss")
			$newRuleName = "DEP$prefix-$($rule.FirewallRuleName)"
			
			Write-Host "~ Deprecating rule '$($rule.FirewallRuleName)' as '$newRuleName' ..." -ForegroundColor Yellow
			Write-Host "  Creating new rule '$newRuleName' for IP range: $($rule.StartIpAddress) -> $($rule.EndIpAddress) ..." -ForegroundColor Gray
			$newRule = New-AzSqlServerFirewallRule -FirewallRuleName $newRuleName -StartIpAddress $rule.StartIpAddress -EndIpAddress $rule.EndIpAddress -ServerName $SqlServerName -ResourceGroupName $SqlResourceGroup -ErrorAction Stop
			
			Write-Host "  Removing old rule '$($rule.FirewallRuleName)' ..." -ForegroundColor Gray
			$result = Remove-AzSqlServerFirewallRule -FirewallRuleName $rule.FirewallRuleName -ServerName $SqlServerName -ResourceGroupName $SqlResourceGroup -Force -ErrorAction Stop
			Write-Host "  Successfully deprecated '$($rule.FirewallRuleName)' -> '$newRuleName'" -ForegroundColor Cyan
		}
	}
	
	Write-Host ""
}

if ($rulesToAdd.Count -gt 0) {
	Write-Host "Found [$($rulesToAdd.Count)] rule(s) to add..."
	
	Foreach ($rule in $rulesToAdd)
	{
		# Add the new rule
		Write-Host "+ Adding new rule '$($rule.FirewallRuleName)' for IP range: $($rule.StartIpAddress) -> $($rule.EndIpAddress) ..." -ForegroundColor Yellow
		$newRule = New-AzSqlServerFirewallRule -FirewallRuleName $rule.FirewallRuleName -StartIpAddress $rule.StartIpAddress `
			-EndIpAddress $rule.EndIpAddress -ServerName $SqlServerName -ResourceGroupName $SqlResourceGroup -ErrorAction Stop
		Write-Host "  Successfully added rule '$($rule.FirewallRuleName)'" -ForegroundColor Green
	}
	
	Write-Host ""
}

if ($rulesToRemove.Count -gt 0) {
	Write-Host "Found [$($rulesToRemove.Count)] redundant rule(s) to remove..."
	
	Foreach ($rule in $rulesToRemove)
	{
		Write-Host "- Removing redundant rule '$($rule.FirewallRuleName)' ..." -ForegroundColor Yellow
		$result = Remove-AzSqlServerFirewallRule -FirewallRuleName $rule.FirewallRuleName -ServerName $SqlServerName -ResourceGroupName $SqlResourceGroup -Force -ErrorAction Stop
		Write-Host "  Successfully removed rule '$($rule.FirewallRuleName)'" -ForegroundColor Cyan
	}
	
	Write-Host ""
}

Write-Host "Script End"
Write-Host ""