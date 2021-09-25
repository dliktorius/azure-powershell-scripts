<#
	.SYNOPSIS
	Loops through all Subscription contexts the executing user has access to and adds CanNotDelete resource locks to all resource groups missing a lock.

	.DESCRIPTION
	Loops through all Subscription contexts the executing user has access to and adds CanNotDelete resource locks to all resource groups missing a lock.
	The first version of this script has no parameters.

	.INPUTS
	None. You cannot pipe objects to Add-AzResourceLocks.ps1.

	.OUTPUTS
	None. This script logs to the Host console.

	.EXAMPLE
	PS> .\Add-AzResourceLocks.ps1

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

$subscriptions = Get-AzSubscription 

#loops through every subscription in the array
foreach ($subscription in $subscriptions) {

	Write-Host $subscription.Name

	Select-AzSubscription -SubscriptionObject $subscription

	#Construct array of resource group in the subscription
	$resourceGroups = Get-AzResourceGroup

	#loops through the resource groups and sets the resource lock on each resource group 
	foreach ($resourceGroup in $resourceGroups) {
		
		Write-Host "Processing: $($resourceGroup.ResourceGroupName)" -ForegroundColor Yellow
		
		$result = (Get-AzResourceLock -ResourceGroupName $resourceGroup.ResourceGroupName) | Where { $_.Properties.level -eq 'CanNotDelete' }
		
		if ($result) {
			Write-Host "$($resourceGroup.ResourceGroupName) already has a delete lock" -ForegroundColor Cyan
		} else {
			# Write-Host $resourceLockStatus
			$result = Set-AzResourceLock -LockName "$($resourceGroup.ResourceGroupName)-delete" -LockLevel CanNotDelete -LockNotes "Locked to prevent accidental deletion" -ResourceGroupName $resourceGroup.ResourceGroupName -Force
			Write-Host "$($resourceGroup.ResourceGroupName) now has a lock set" -ForegroundColor Green
		}
	}
}