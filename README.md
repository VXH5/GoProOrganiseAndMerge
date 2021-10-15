# GoProOrganiseAndMerge
PowerShell Script to Automatically Name, Organise, and Merge GoPro Videos.
Does the following:
- Scans files on SD card. If they all share the same recording date. Use that date for renaming.
- Scans files on SD card. If they all share the same GPS Location, look up in Locations.txt for the name of the location, and use that for renaming.
- Ask for a Location to be used for renaming.
- Renames files based on the date of the recording, and location.
- Merges together files if they are from the same recording session
- Creates a backup of original, un-merged files to be kept for 60 days

Note. Files often do not contain GPS location data, see below for an FAQ on how to get GPS added -
https://community.gopro.com/t5/GoPro-Telemetry-GPS-overlays/GoPro-GPS-not-working-Performance-stickers-and-telemetry-FAQ/gpm-p/419554

Made for Hero 6 Black and newer's naming convention. Tested with Hero 9 Black.
https://community.gopro.com/t5/en/GoPro-Camera-File-Naming-Convention/ta-p/390220

Prerequisites
MKVToolsNIX installed in C:\Program Files\
https://mkvtoolnix.download/
FFProbe.exe from FFMPEG Tools
https://www.gyan.dev/ffmpeg/builds/

How To Use
Edit the PowerShell Script for the following variables-

$GoProSource = "E:\DCIM\100GOPRO\"
Source Location for GoPro Files as seen by Windows.
Note: This does not work with the GoPro connected directly to a PC, you need to use a SD Card Reader to allow windows to see the drive as an attached disk, instaed of an MTP Device.

$SourceFolder = "C:\Source"
This is a 'staging' folder. Files are copied here, then used as the source for the merging,renaming process. Saves wear on the SD cards.

$DestinationDir = "C:\Destination"
Final Destination for GoPro Videos. Sub Folders are created based on the date and location of the videos.

$BackupDir = "C:\Backup\"
Copy of the original, unmerged files. Kept for 60 Days.

$LocationsCSV = "C:\Locations.txt"
Store of known locations based on GPS coordinates.

$FFProbe = "C:\ffprobe.exe"
Location of the FFProbe.exe executable

$LogLocation = "C:\Backup\Log\" + (Get-Date -Format yyy-MM-dd) + ".txt"
Location of Log Files.

How to Run
Allow running of Powershell scripts.
e.g. - powershell.exe -ExecutionPolicy UnRestricted
See - https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.1
