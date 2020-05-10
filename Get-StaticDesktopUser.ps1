#region help text

<#
.SYNOPSIS
	Creates a text file of users assigned to static desktops in a Citrix XenDesktop 
	7.x/18xx/19xx Site.
.DESCRIPTION
	Creates a text file of users assigned to static desktops in a Citrix XenDesktop 
	7.x/18xx/19xx Site.
	
	This script runs best in PowerShell version 5 or later.

	You do NOT have to run this script on a Controller. This script was developed and run 
	from a Windows 10 VM.
	
	You can run this script remotely using the -AdminAddress (AA) parameter.
	
	This script supports Linux and Windows Delivery Groups.
	
	Creates an output file named after a Delivery Group.
.PARAMETER AdminAddress
	Specifies the address of a XenDesktop controller where the PowerShell snapins will 
	connect. 

	This can be provided as a hostname or an IP address. 
	This parameter defaults to Localhost.
	This parameter has an alias of AA.
.PARAMETER DeliveryGroupName
	By default, the script processes all Delivery Groups that deliver Static desktops.
	This is where the properties DeliveryType equals DesktopsOnly and DesktopKind 
	equals Private.
	
	Use this parameter to specify a single Delivery Group.
	
	This parameter defaults to all Static Desktop Delivery Groups.
	This parameter has an alias of DGN.
.PARAMETER Folder
	Specifies the optional output folder to save the output report. 
.EXAMPLE
	PS C:\PSScript > .\Get-StaticDesktopUser.ps1
	
	Processes all Delivery Groups where DeliveryType equals DesktopsOnly and 
	DesktopKind equals Private.
	Uses the computer running the script for the AdminAddress.
.EXAMPLE
	PS C:\PSScript > .\Get-StaticDesktopUser.ps1 -AdminAddress DDC01
	
	Processes all Delivery Groups where DeliveryType equals DesktopsOnly and 
	DesktopKind equals Private.
	Uses DDC01 for the AdminAddress.
.EXAMPLE
	PS C:\PSScript > .\Get-StaticDesktopUser.ps1 -DeliveryGroupName StaticDesktops
	
	Processes the Delivery Group StaticDesktops if DeliveryType equals DesktopsOnly 
	and DesktopKind equals Private.
	Uses the computer running the script for the AdminAddress.
.EXAMPLE
	PS C:\PSScript > .\Get-StaticDesktopUser.ps1 -DGN StaticDesktops -AdminAddress DDC01
	
	Processes the Delivery Group StaticDesktops if the DesktopKind is Private and 
	DeliveryType equals DesktopsOnly.
	Uses DDC01 for the AdminAddress.
.EXAMPLE
	PS C:\PSScript > .\Get-StaticDesktopUser.ps1 -Folder \\FileServer\ShareName
	
    Processes all Delivery Groups where DeliveryType equals DesktopsOnly and 
    DesktopKind equals Private.
	Uses the computer running the script for the AdminAddress.
	Output file(s) will be saved in the path \\FileServer\ShareName
.INPUTS
	None.  You cannot pipe objects to this script.
.OUTPUTS
	No objects are output from this script.  
	This script creates a text file for each Delivery Group processed.
.NOTES
	NAME: Get-StaticDesktopUser.ps1
	VERSION: 1.00
	AUTHOR: Carl Webster
	LASTEDIT: March 2, 2019
#>

#endregion

#region script parameters

[CmdletBinding(SupportsShouldProcess = $False, ConfirmImpact = "None", DefaultParameterSetName = "") ]

Param(
	[parameter(Mandatory=$False)] 
	[ValidateNotNullOrEmpty()]
	[Alias("AA")]
	[string]$AdminAddress="Localhost",

	[parameter(Mandatory=$False)] 
	[Alias("DGN")]
	[string]$DeliveryGroupName="",	

	[parameter(Mandatory=$False)] 
	[string]$Folder=""
	
	)

#endregion

#region script change log	
#webster@carlwebster.com
#@carlwebster on Twitter
#http://www.CarlWebster.com
#Created on March 1, 2019 from a request by Matt Lovett
#
#Released to the community on March 5, 2019 at the CUGC Texas XL Event in Austin, TX
#
#V1.00
#	Initial release
#endregion

#region initial variable testing and setup
Set-StrictMode -Version 2

#force  on
$PSDefaultParameterValues = @{"*:Verbose"=$True}
$SaveEAPreference = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'

If($Folder -ne "")
{
	Write-Verbose "$(Get-Date): Testing folder path"
	#does it exist
	If(Test-Path $Folder -EA 0)
	{
		#it exists, now check to see if it is a folder and not a file
		If(Test-Path $Folder -pathType Container -EA 0)
		{
			#it exists and it is a folder
			Write-Verbose "$(Get-Date): Folder path $Folder exists and is a folder"
		}
		Else
		{
			#it exists but it is a file not a folder
			Write-Error "Folder $Folder is a file, not a folder.  Script cannot continue"
			Exit
		}
	}
	Else
	{
		#does not exist
		Write-Error "Folder $Folder does not exist.  Script cannot continue"
		Exit
	}
}
ElseIf($Folder -eq "")
{
	$pwdpath = $pwd.Path
}
Else
{
	$pwdpath = $Folder
}

If($pwdpath.EndsWith("\"))
{
	#remove the trailing \
	$pwdpath = $pwdpath.SubString(0, ($pwdpath.Length - 1))
}
#endregion

#region validation functions
Function Check-NeededPSSnapins
{
	Param([parameter(Mandatory = $True)][alias("Snapin")][string[]]$Snapins)

	#Function specifics
	$MissingSnapins = @()
	[bool]$FoundMissingSnapin = $False
	$LoadedSnapins = @()
	$RegisteredSnapins = @()

	#Creates arrays of strings, rather than objects, we're passing strings so this will be more robust.
	$loadedSnapins += Get-PSSnapin | ForEach-Object {$_.name}
	$registeredSnapins += Get-PSSnapin -Registered | ForEach-Object {$_.name}

	ForEach($Snapin in $Snapins)
	{
		#check if the snapin is loaded
		If(!($LoadedSnapins -like $snapin))
		{
			#Check if the snapin is missing
			If(!($RegisteredSnapins -like $Snapin))
			{
				#set the flag if it's not already
				If(!($FoundMissingSnapin))
				{
					$FoundMissingSnapin = $True
				}
				#add the entry to the list
				$MissingSnapins += $Snapin
			}
			Else
			{
				#Snapin is registered, but not loaded, loading it now:
				Add-PSSnapin -Name $snapin -EA 0 *>$Null
			}
		}
	}

	If($FoundMissingSnapin)
	{
		Write-Warning "Missing Windows PowerShell snap-ins Detected:"
		$missingSnapins | ForEach-Object {Write-Warning "($_)"}
		Return $False
	}
	Else
	{
		Return $True
	}
}
#endregion

$StartTime = Get-Date

#check for required Citrix snapin
If(!(Check-NeededPSSnapins "Citrix.Broker.Admin.V2"))
{
	#We're missing Citrix Snapins that we need
	$ErrorActionPreference = $SaveEAPreference
	Write-Error "`nMissing Citrix PowerShell Snap-ins Detected, check the console above for more information. 
	`nAre you sure you are running this script against a XenDesktop 7.0 or later Delivery Controller? 
	`n`nIf you are running the script remotely, did you install Studio or the PowerShell snapins on $($env:computername)?
	`n`nScript will now close."
	Exit
}

Write-Verbose "$(Get-Date): Retrieving Delivery Group data"
If($DeliveryGroupName -eq "")
{
	$DeliveryGroups = Get-BrokerDesktopGroup -AdminAddress $AdminAddress `
	-filter {DeliveryType -eq "DesktopsOnly" -and DesktopKind -eq "Private"} -EA 0
	
	If(!$?)
	{
		Write-Error "Unable to retrieve Delivery Groups that deliver Static Desktops.
		`n`nScript will now close."
		Exit
	}
	ElseIf($? -and $Null -eq $DeliveryGroups)
	{
		Write-Error "No Delivery Groups were found that deliver Static Desktops.
		`n`nScript will now close."
		Exit
	}
}
Else
{
	$DeliveryGroups = Get-BrokerDesktopGroup -AdminAddress $AdminAddress `
	-filter {DeliveryType -eq "DesktopsOnly" -and DesktopKind -eq "Private"} `
	-Name $DeliveryGroupName -EA 0

	If(!$?)
	{
		Write-Error "Unable to retrieve Delivery Group $DeliveryGroupName.
		`n`nScript will now close."
		Exit
	}
	ElseIf($? -and $Null -eq $DeliveryGroups)
	{
		Write-Error "Delivery Group $DeliveryGroupName has no Static Desktops.
		`n`nScript will now close."
		Exit
	}
}

Write-Verbose "$(Get-Date): Processing Delivery Group data"
ForEach($DG in $DeliveryGroups)
{
	Write-Verbose "$(Get-Date): `tRetrieving static desktops for Delivery Group $($DG.name)"
	$Machines = Get-BrokerMachine -Filter {IsAssigned -eq $True} -DesktopGroupName $DG.Name `
	-EA 0 | Sort-Object DNSName
	
	If(!$?)
	{
		Write-Warning "`t`tNo desktops were found for Delivery Group $($DG.Name)"
	}
	Else
	{
		$UserNames = New-Object System.Collections.ArrayList
		
		ForEach($Machine in $Machines)
		{
			Write-Verbose "$(Get-Date): `t`tProcesing desktop $($Machine.DNSName)"
			If($null -ne $Machine.LastConnectionUser)
			{
				$UserNames.Add($Machine.LastConnectionUser) > $Null
			}
		}
		
		#sort users and remove duplicates
		$UserNames = $UserNames | Sort-Object -Unique
		$OutputFile = "$($pwdpath)\$($DG.Name) Static Users.txt"
		Write-Verbose "$(Get-Date): Output text file $OutputFile"
		Out-File -FilePath $OutputFile -Encoding ascii -InputObject $UserNames 4>$Null
	}
}

Write-Verbose "$(Get-Date): Script started: $($StartTime)"
Write-Verbose "$(Get-Date): Script ended: $(Get-Date)"
$runtime = $(Get-Date) - $StartTime
$Str = [string]::format("{0} days, {1} hours, {2} minutes, {3}.{4} seconds",
	$runtime.Days,
	$runtime.Hours,
	$runtime.Minutes,
	$runtime.Seconds,
	$runtime.Milliseconds)
Write-Verbose "$(Get-Date): Elapsed time: $($Str)"