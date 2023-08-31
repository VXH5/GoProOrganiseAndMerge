param (
  [switch]$YouTubeUpload = $True
)


#Define Variables
$GoProSource = "E:\DCIM\100GOPRO\"
$SourceFolder = "C:\Source"
$DestinationDir = "C:\Destination"
$BackupDir = "C:\Backup\"
$LocationsCSV = "C:\Locations.txt"
$FFProbe = "C:\ffprobe.exe"
$Upload = "C:\Upload\"
$twilioSid = "XXXXXXXXXXXXXXXXXXXXXXX"
$twilioToken = "XXXXXXXXXXXXXXXXXXXXXXX"
$twilioFromNumber = "+XXXXXXXXXXXXXXXXXXXXXXX"
$toNumber = "+XXXXXXXXXXXXXXXXXXXXXXX"
$slackURI = "https://hooks.slack.com/services/XXXXXXXXXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXX"
$url = "https://api.twilio.com/2010-04-01/Accounts/$twilioSid/Messages.json"

$LogLocation = "C:\Log\" + (Get-Date -Format yyyy-MM-dd) + ".txt"

#If There are no files in Source; Exit
if (!(Test-Path -Path $GoProSource)) {
    Write-Host 'SD Card Not Mounted, Ending'
    Exit
    }
    else {
        $AllSourceFiles = (Get-ChildItem -Filter *.mp4 -Path $GoProSource)
        if ($AllSourceFiles.length -eq 0) {
            Write-Host 'SD Card Mounted, no mp4 files for import'
            Exit
        }
    }

Start-Transcript -Path $LogLocation -Append

# Send Slack message saying import has started
$payload = @"
    {
    "text": "Starting GoPro Import"
    }
"@
Invoke-RestMethod -Uri $slackURI -Method Post -Body $Payload | Out-Null

# Create a Twilio credential object for HTTP basic auth
$twilioTokenSecure = $twilioToken | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($twilioSid, $twilioTokenSecure)

#If all files have the same date, use that, else ask
$OriginalFiles = Get-ChildItem -Path $GoProSource
$Dates=ForEach ($OriginalFile In $OriginalFiles) {
    $OriginalFile | Select-Object -ExpandProperty CreationTime | Get-Date -format yyyy-MM-dd
    }

if (($Dates | Select -Unique).Count -eq 1) {
    $Date = $Dates | Select-Object -first 1
    }
else {
    #Ask for Date
    $Date = Read-Host 'Date of Files'
    }

#If all files have the same GPS location, look up based on Locations.txt, if no match, add to txt. If no gps, ask
$ArrayOfEvents = @()
$GPSfiles = Get-ChildItem -Path $GoProSource -Filter *.mp4
ForEach ($IndivGPSFile In $GPSfiles) {

    $Coordinate = & $FFProbe $IndivGPSFile.FullName 2>&1 | %{ "$_" } | Select-string -pattern location-eng | Out-String 

    if ($Coordinate) {
        $RoughCoordinateLat = $Coordinate.Substring(25,5)
        $RoughCoordinateLon = $Coordinate.Substring(34,5)
        $RoughCoordinate = $RoughCoordinateLat + "," + $RoughCoordinateLon
     
        foreach ($Event in (Import-Csv $LocationsCSV)) {
            if ($Event.RoughCoordinate -eq $RoughCoordinate) {
            $ArrayOfEvents += $Event.Event
            }
        }

     }
}

if($ArrayOfEvents){

    if (($ArrayOfEvents | Select -Unique).Count -eq 1) {
        $Location = $ArrayOfEvents | Select-Object -first 1
        }
    else {
        # Make API request, selecting JSON properties from response
        $params = @{ To = $toNumber; From = $twilioFromNumber; Body = "Respond With Name" }
        Invoke-WebRequest $url -Method Post -Credential $credential -Body $params -UseBasicParsing |
        ConvertFrom-Json | Select sid, body
        # Send Slack update
        $payload = @"
            {
            "text": "Waiting for SMS with Location"
            }
"@
        Invoke-RestMethod -Uri $slackURI -Method Post -Body $Payload | Out-Null

        # Wait 60 Seconds
        sleep 60

        # Waiting for new SMS within the last 2 hours
        while ($true) {
            Write-Host "Checking for new messages"
            $response = Invoke-RestMethod -Method GET -Uri $url -Credential $Credential
            # Formating response to only include useful info
            $messages = $response.messages | Select date_updated, from, to, body | where-object -Property 'to' -like $twilioFromNumber | where-object -Property 'from' -like $toNumber
            $latestMessage = $messages | Select-Object -first 1 
            # Remove timezone from date recieved, and convert to date
            $latestMessage.date_updated = $latestMessage.date_updated.Substring(0,$latestMessage.date_updated.Length-6)
            $latestMessage.date_updated = [datetime]::parseexact($latestMessage.date_updated, "ddd, dd MMM yyyy HH':'mm':'ss", $null)
            # If message is within last 2 hours (UTC time), mark as location after removing new lines/spaces and end
            if ($latestMessage.date_updated -gt ( Get-Date).AddHours(-2)) {
                $Location = $latestMessage.body
                $Location = $Location -replace '(^\s+|\s+$|`n)','' -replace '\s+',''
                Write-Host "Location is " $Location

                # Send Slack update
                $payload = @"
                {
                "text": "SMS Location Recieved - $Location"
                }
"@
                Invoke-RestMethod -Uri $slackURI -Method Post -Body $Payload | Out-Null

                break
                }
            else {
                Write-Host "Waiting for 60 seconds for text message"
                sleep 60
                }
            }
        Add-Content -Path $LocationsCSV -Value """$Location"",""$RoughCoordinate"""
        }
    }
else {
    #Ask for Location
    # Send Message via Twilio
    # Make API request, selecting JSON properties from response
    $params = @{ To = $toNumber; From = $twilioFromNumber; Body = "Respond With Name" }
    Invoke-WebRequest $url -Method Post -Credential $credential -Body $params -UseBasicParsing |
    ConvertFrom-Json | Select sid, body
    # Wait 60 Seconds
    sleep 60

    # Waiting for new SMS within the last hour
    while ($true) {
        Write-Host "Checking for new messages"
        $response = Invoke-RestMethod -Method GET -Uri $url -Credential $Credential
        # Formating response to only include useful info
        $messages = $response.messages | Select date_updated, from, to, body | where-object -Property 'to' -like $twilioFromNumber | where-object -Property 'from' -like $toNumber
        $latestMessage = $messages | Select-Object -first 1 
        # Remove timezone from date recieved, and convert to date
        $latestMessage.date_updated = $latestMessage.date_updated.Substring(0,$latestMessage.date_updated.Length-6)
        $latestMessage.date_updated = [datetime]::parseexact($latestMessage.date_updated, "ddd, dd MMM yyyy HH':'mm':'ss", $null)
        # If message is within last 2 hours (UTC time), mark as location after removing new lines/spaces and end
        if ($latestMessage.date_updated -gt ( Get-Date).AddHours(-2)) {
            $Location = $latestMessage.body
            $Location = $Location -replace '(^\s+|\s+$|`n)','' -replace '\s+',''
            Write-Host "Location is " $Location

            # Send Slack update
            $payload = @"
            {
            "text": "SMS Location Recieved - $Location"
            }
"@
            Invoke-RestMethod -Uri $slackURI -Method Post -Body $Payload | Out-Null

            break
        }
        else {
        Write-Host "Waiting for 60 seconds"
        sleep 60
        }
    }
}

#Copy Files from USB
if (Test-Path -Path $GoProSource) {
    #Copy Files
    Write-Host "Copying Videos"
    robocopy $GoProSource $SourceFolder /MOV /NJH /NJS
    }


#Create New folder in destination folder with todays date if it doesn't exist
$Destination = "$DestinationDir$Date - $Location\"
if (!(Test-Path -path $Destination)) {
    New-Item $Destination -Type Directory | Out-Null
    }


#Move Files into Folders based on video within SourceFolder
Write-Host "Organising Videos"
Set-Location -Path $SourceFolder
$AllFiles = (Get-ChildItem -Filter *.mp4 -Path $SourceFolder)

#If There are files
if ($AllFiles.length -gt 0) {
    ForEach ($IndivFile In $AllFiles) {
    #Get Video Number
    $VideoNumber = $IndivFile.name.Substring(4).Split(".")[0]

    if (-not (Test-Path -Path $VideoNumber)) {
        #Create Folder with Video Number
        New-Item $VideoNumber -Type Directory | Out-Null
        }
    #Move file to Video Number Folder
    Move-Item $IndivFile -Destination $VideoNumber
    }
}
else {
    "No mp4 files found to process in directory " + $Destination
    }


#Merge files & Move into new dir
Write-Host "Merging Videos"

#Get all Folder in the directory
$AllFolders = (Get-ChildItem -Directory -Path $SourceFolder)

#Only continue if there is more then 0 folder
if ($AllFolders.length -gt 0) {

    #Iterate through each folder
    ForEach ($Folder in $AllFolders) {

        #Get a list of all files within relevant folder
        Set-Location -Path $SourceFolder
        $MergeFiles = @(Get-ChildItem -Path $Folder)

        #If there is only one file
        if ($MergeFiles.Count -eq 1) {

            #Copy File to Dir and rename adding date before
            #'Only 1 Merge File: ' + $MergeFiles + ' To Go Into Directory: ' + $Destination
            Copy-Item $MergeFiles.FullName -Destination $Destination\$($Date + '-' + $Location + '-' + $Folder.Basename + $MergeFiles.Extension)
    
        }

        #else; there are multiple files in the folder
        else {

    
            $MergeFilesFullname = $MergeFiles.FullName

            #Define Merged output name & Location
            Set-Location -Path $Destination
            $outputMerged = $Date + '-' + $Location + '-' + $Folder + '-Merged' + '.mkv'

            #define mkvmerge settings
            $start = '"' + 'C:\Program Files\MKVToolNix\mkvmerge.exe" --ui-language en --gui-mode --output ^"' + $outputMerged + '^" --language 0:und --language 1:und ^"^(^" ^"'
            $cmdMerge = $start + ($MergeFilesFullname -join '^" ^"^)^" + ^"^(^" ^"') + '^" ^"^)^" --track-order 0:0,0:1 '
            

            #Check if merged file exists
            if (!(Test-Path $outputMerged -PathType Leaf)) {
                 #run mkvmerge
                 "Running MKVMerge On $Folder"
                 cmd /c $cmdMerge | ForEach-Object -Process {
                    if ($_ -match "^#GUI#progress (\d+)%") {
                        Write-Progress -Activity "Merging $Folder" -PercentComplete $Matches.1 -Status "$($Matches.1)%"
                    }
                 }


            }
            
              
        }
    }
}
else {
    "No Folders found to process in directory " + $Destination
    }

# Open File Explorer to new files if Firefox/VLC are not running
if (!(Get-Process | ? {$_.ProcessName -like "*Firefox*"})) {
    if (!(Get-Process | ? {$_.ProcessName -like "*VLC*"})) {
        Write-Host "Opening File Explorer"
        start-process explorer -WindowStyle Maximized -ArgumentList $Destination
        }
    }

# Send message saying videos are ready
$params = @{ To = $toNumber; From = $twilioFromNumber; Body = "Videos are now available. SD Card can be removed" }
Invoke-WebRequest $url -Method Post -Credential $credential -Body $params -UseBasicParsing |
ConvertFrom-Json | Select sid, body

# Send Slack update
$payload = @"
{
"text": "Videos are now available. SD Card can be removed"
}
"@
Invoke-RestMethod -Uri $slackURI -Method Post -Body $Payload | Out-Null

#Create New folder in the backupLocation with todays date if it doesn't exist
Write-Host "Making Backup of Videos"
if (!(Test-Path -path "$BackupDir\$Date - $Location\")) {
    New-Item "$BackupDir\$Date - $Location\" -Type Directory | Out-Null
    }

#Move All Originals to Backup Location
robocopy "$SourceFolder\" "$BackupDir\$Date - $Location" /MOV /NJH /NJS /E

#Delete empty folders in Source Location
Get-ChildItem $SourceFolder -Recurse -Force -ea 0 |
? {$_.PsIsContainer -eq $True} |
? {$_.getfiles().count -eq 0} |
ForEach-Object {
    $_ | del -Force -Recurse | Out-Null
    }

#Delete files older than 60 Days
Write-Host "Deleting Old Backups"
Get-ChildItem $BackupDir -Recurse -Force -ea 0 |
? {!$_.PsIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-60)} |
ForEach-Object {
   $_ | del -Force  | Out-Null
    }

#Delete empty folders and subfolders
Get-ChildItem $BackupDir -Recurse -Force -ea 0 |
? {$_.PsIsContainer -eq $True} |
? {$_.getfiles().count -eq 0} |
ForEach-Object {
    $_ | del -Force -Recurse  | Out-Null
    }

#Upload to YouTube

if ($YouTubeUpload)
{
    $FolderName = Split-Path $Destination -Leaf
    Set-Location $Destination

    #Convert Date to UK Style
    $Date = $FolderName.Substring(0,10)
    $Date = [DateTime]::ParseExact($Date, 'yyyy-MM-dd', $null)
    $DateUK = $Date.ToString('dd-MM-yyyy')

    #Get Location from Folder name
    $Location = $UploadFile.Name.Substring(11)
    $Location = $Location.Substring(0,$Location.Length-16)

    #Create metadat json file containing Playlist Name
    $PlaylistName = $DateUK + " - " + $Location
    (Get-Content "$Upload\template.json") -Replace 'Template', $PlaylistName | Set-Content "$Upload\data.json"

    $AllUploadFiles = (Get-ChildItem -Path $Destination)
    ForEach ($UploadFile in $AllUploadFiles)
        {
        if($UploadFile -like '*Merged*') {
            $LocationName = $UploadFile.Name.Substring(11)
            $LocationName = $LocationName.Substring(0,$LocationName.Length-11)
        } else {
            $LocationName = $UploadFile.Name.Substring(11)
            $LocationName = $LocationName.Substring(0,$LocationName.Length-4)
        }

        #Set Upload File Name
        $UploadName = $DateUK + " - " + $LocationName
        write-host "Uploading - " $UploadName "To - " $PlaylistName

        #Upload
        Set-Location $Upload
        ./youtubeuploader_windows_amd64.exe `
        -filename $UploadFile.FullName `
        -title $UploadName `
        -description $UploadName `
        -secrets "$Upload\client_secrets.json" `
        -metaJSON "$Upload\data.json" `
        -ratelimit 5000 -limitBetween 08:00-01:00

        # Send Slack update
        $payload = @"
        {
        "text": "Uploading $UploadName"
        }
"@
        Invoke-RestMethod -Uri $slackURI -Method Post -Body $Payload | Out-Null
        }
}

# Send message saying videos are ready
$params = @{ To = $toNumber; From = $twilioFromNumber; Body = "Videos are now available on YouTube" }
Invoke-WebRequest $url -Method Post -Credential $credential -Body $params -UseBasicParsing |
ConvertFrom-Json | Select sid, body

# Send Slack update
$payload = @"
{
"text": "Videos are now available Youtube. Script Complete"
}
"@
Invoke-RestMethod -Uri $slackURI -Method Post -Body $Payload | Out-Null


Stop-Transcript 
