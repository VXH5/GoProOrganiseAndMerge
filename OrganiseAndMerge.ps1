#Define Variables
$GoProSource = "E:\DCIM\100GOPRO\"
$SourceFolder = "C:\Source"
$DestinationDir = "C:\Destination"
$BackupDir = "C:\Backup\"
$LocationsCSV = "C:\Locations.txt"
$FFProbe = "C:\ffprobe.exe"
$LogLocation = "C:\Backup\Log\" + (Get-Date -Format yyy-MM-dd) + ".txt"

Start-Transcript -Path $LogLocation -Append

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
    $Date = Read-Host 'Date of Race Meeting'
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
    #Ask for Location
    $Location = Read-Host 'Name of Race Meeting'
    Add-Content -Path $LocationsCSV -Value """$Location"",""$RoughCoordinate"""
    }
}
else{
    #Ask for Location
    $Location = Read-Host 'Name of Race Meeting'
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

Stop-Transcript 
