function global:Find-InFiles
{
    param(
		   [parameter(Mandatory=$true)]
		   [string] $Pattern,

		   [parameter(Mandatory=$false)]
		   [string] $Filter="*"
	 )

    $excludes = @("*.exe", "*.dll", "*~")
    [array]$results = Get-ChildItem -Recurse -Exclude $excludes -Include ("*." + $Filter) | Select-String $Pattern
    if($results.Count -eq $null) {
        write-host Not found.
        return;
    }
	
    [array]$outResults = $()
    $i = 0; 
    $results | %{
        set-variable $i -value $_.Path -scope Global
	$outResults += "(${i}) " + $_.Filename + " ln" + $_.LineNumber + ": " + $_.Line
	$i++
    }
    $outResults
}

function global:reconfig
{
	tabadmin stop -c vizportal0
	tabadmin config -c vizportal0
	tabadmin start -c vizportal0
}

function global:GoTo-File
{
    <# 
    .SYNOPSIS
    Recursively searches for files and if a single match is found, takes you there. This is a Push operation so you may pop to return. 
    
    .PARAMETER FileName
    The list of files to look for. This may include wildcards.
    #>
    
    param(
        [parameter(Mandatory=$true)]
        [string] $FileName 
    )

    [array]$location = Get-ChildItem * -Recurse -Include $FileName 

    if($location -eq $null)
    {
        write-host "file not found" ; return 
    }    

    $selection = 0
    if ($location.Count -gt 1)
    {
        write-host "Multiple matches found:`n"
        write-host "Index `t Full Path"
        $i = 0
        $location | %{ 
		write-host -NoNewLine $i "`t"
		write-output $_.FullName 
		$i++ 
	}

        $selection = read-host "`nEnter Selection"
        
        if (0..($location.Count - 1) -notcontains $selection)
        {
            return "invalid choice"
        }
    }

    if(test-path $location[$selection] -pathType container) {
        pushd $location[$selection]
    }
    else {
        pushd $location[$selection].Directory
    }
}

function global:touch([string]$file){ set-content -Path ($file) -Value $null }

function global:reload(){ & $profile }

function global:root()
{
    pushd $env:srcbase
}

function global:deploy-demo()
{
    iisreset-aconcord01

    $ServerBinDir = "\\aconcord02\c$\Program Files\Microsoft Dynamics CRM\server\bin\assembly"
    $LocalBinDir = "c:\users\aconcord\documents\visual studio 2010\projects\crmvssolution1\crmvssolution1\crmpackage\bin\debug\"

    # Binaries
	write-host "Deploying binaries..."
    copy ($LocalBinDir + "*.pdb") $ServerBinDir
    copy ($LocalBinDir + "*.dll") $ServerBinDir

    # Src files
	write-host "Deploying src files..."
    $LocalSrc = "c:\users\aconcord\documents\visual studio 2010\projects\crmvssolution1"
    copy -recurse -force $LocalSrc "\\aconcord02\c$"
	
	write-host "Done."
}

function global:Enable-PluginDebugging
{
	<#
	.SYNOPSIS
	Sets HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\MSCRM\SandboxDebugPlugins to 1 on the server specified

	.PARAMETER ServerName
	The server on which the reg key will be set
	#>

	param(
		[parameter(Mandatory=$true)]
		[string] $ServerName
	)
	
	Invoke-Command -ComputerName:$ServerName -Credential:$ServerName\Administrator -ScriptBlock {
		New-Item -ItemType:DWord -Value:1 -Name:SandboxDebugPlugins -Path:HKLM:\SOFTWARE\Microsoft\MSCRM
	}
}

function global:Search-Path
{
    <# 
    .SYNOPSIS
    Searches for file in the path and prints out all the locations where it is found. 
    
    .PARAMETER FileName
    The file to look for. This may include wildcards.
    #>
    
    param(
        [parameter(Mandatory=$true)]
        [string] $FileName 
    )
    
    $env:path.split(";") | % {
        if ($_ -and (test-path $_))
        {
            $Patterns = $FileName,($FileName + ".exe"),($FileName + ".bat"),($FileName + ".cmd")
            get-childitem (join-path $_ *) -include $Patterns | % {
                write-host $_.FullName
            }
        }
    }
}

function global:af {devenv $env:basedir\src\certified\ActivityFeeds\Current\ActivityFeeds.sln}
function global:cdaf {cd $env:basedir\src\certified\ActivityFeeds\Current}
function global:sync 
{
	p4 sync
	p4 resolve -am
}
function global:opened {sd opened}

function global:GetNextAvailableHostname()
{
	$hostname = $null;
	try
	{
		for($i = 1; $true; $i++)
		{
			$hostname = BuildAconcordHostname($i); 
			[void][System.Net.Dns]::GetHostAddresses($hostname);
		}
	}
	catch [System.Net.Sockets.SocketException] { # thrown when hostname doesn't resolve 
	}

	$hostname; 
}

function global:BuildAconcordHostname([int32]$i)
{
	if($i -lt 1)
	{
		throw New-Object System.ArgumentException "Argument must be greater than 0";
	}

	$suffix = "{0:D2}" -f $i;
	return "aconcord$suffix";
}

function global:Build-HostedVM()
{
	[string]$hostname = GetNextAvailableHostname; 
	write-host "Will build: " + $hostname; 
	write-host "with command: "; 
	write-host "E:\crm\bin\Microsoft.ImageBuilder.Client.Submitter.exe /JobDefinition:E:\crm\v5MainFb2.xml /MachineName:$hostname /OutputMode:Host /Location:REDMOND"
}

function global:Build-VMImage()
{
	[string]$hostname = GetNextAvailableHostname;
	E:\crm\bin\Microsoft.ImageBuilder.Client.Submitter.exe /JobDefinition:E:\crm\v5MainFb2.xml /MachineName:$hostname /OutputPath:\\Joule\ImcomingVMs /Location:REDMOND
}


function global:Sd-Move()
{
    <# 
    .SYNOPSIS
    Moves a file in source depot to a new location. 
    
    .PARAMETER Source
    The source file. 
    
    .PARAMETER Destination	
    The destination file or directory.
    #>

    param(
       [parameter(Mandatory=$true)]
       [string] $Source, 
       [string] $Destination
    )

    # Verify old exists
    if ((Test-Path -PathType Leaf $Source) -eq $false)
    {
        write-host "$Source does not exist or is not a file"
	return; 
    }

    # If new exists, prompt for overwrite
    if (Test-Path -PathType Leaf $Destination)
    {
        write-host "$Destination exists, use -Force to overwrite"
	return; 
    }
    # Handle the case where the destination is a directory. 
    elseif(Test-Path -PathType Container $Destination)
    {
        $file = Get-ChildItem $Source; 
        $Destination += "\" + $file.Name;
    }

    # Integrate to new
    sd integrate $Source $Destination
	
    if (!$?)
    {
        return; 
    } 

    # Delete old
    sd delete $Source
}


function global:Build-And-Refresh-Test()
{
	build -c 
	if($LastExitCode -eq 0 -and !(test-path -path buildd.err)) {
		refreshtest 
	}
}
# PS Bookmarks TODO: Make this into a module
# TODO: serialization/deserialization 
function global:Get-Bookmark()
{
	write-host $Bookmarks
}


[array]$global:Bookmarks = @(); 
if(Test-Path $home\PS_bookmarks)
{
	[array]$global:Bookmarks = Get-Content $home\PS_bookmarks
}

function global:Set-Bookmark()
{
    param(
        [parameter(Mandatory=$true)]
        [string] $Description
    )
	write-host "Adding bookmark for $pwd"; 
    	$global:Bookmarks += , @($pwd, $Description); 

	# TODO: make this async if possible
	$stream = [System.IO.StreamWriter] "$home\PS_bookmarks"
	$global:Bookmarks | % {
		if($_.length -ne 0)
		{
			$stream.WriteLine($_)
		}
	}
	$stream.close()
}

function global:BuildAndBeep()
{
	build $args;
	beep;
}

function global:Root()
{
	pushd $env:root
}
function global:BuildScriptSharp()
{
	Root
	msbuild /v:m vqlweb\scriptsharp\Tableau.Javascript.sln
	popd
}

function global:BuildScriptSharpAndTest()
{
	Root
	try{
		BuildScriptSharp
		rake test:jasmine
	}
	finally
	{
		popd
	}
}

function global:Build()
{
	Root
	StopServer
	rake build:desktop
	StartServer
	popd
}

function global:Deploy()
{
	Root
	StopServer
	rake deploy
	StartServer
	popd
}

function global:WebStorm
{
    & 'C:\Program Files (x86)\JetBrains\WebStorm 6.0.1\bin\WebStorm.exe';
}

function global:StopServer()
{
	tabadmin stop -c $env:ServerConfig
}

function global:StartServer()
{
	tabadmin start -c $env:ServerConfig
}

function global:RestartServer()
{
	StopServer
	StartServer
}

function global:BrokenRake
{
	$rakeArgs = "-f $env:Root\Rakefile $args"
	& $env:Root\..\workgroup-support\jruby\bin\rake.bat $rakeArgs
}

function global:S#()
{
	pushd $env:root\vqlweb\scriptsharp\src
}

function global:auto-resolve
{
	p4 resolve -am 
}

# Powertab
#Import-Module "PowerTab" -ArgumentList "C:\Users\aconcord\Documents\WindowsPowerShell\PowerTabConfig.xml"

# Update path
$env:Path += ";$env:Root\..\tableau-1.3\tools"

# Aliases
set-alias emacs "c:\Program Files (x86)\Emacs-24.3\bin\emacs.exe"
set-alias which Search-Path
set-alias b Build
set-alias am auto-resolve
set-alias .. cd..
set-alias Out-Clipboard $env:SystemRoot\system32\clip.exe

function Get-ClipboardText()
{
    Add-Type -AssemblyName System.Windows.Forms
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.Paste()
    $tb.Text
}

# Environement Vars
$env:Root = "$env:DLL_HOME.."
# $env:EDITOR = "C:\Windows\vim.bat"
$env:EDITOR = "C:\Program Files\Sublime Text 2\sublime_text.exe"
$env:GL_CONFIG = "minelocal"

if ( !$env:ServerConfig )
{
    $env:ServerConfig = "nazgul0"
}

write-host -Foreground Green User Profile Loaded
write-host

