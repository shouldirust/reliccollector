#
# Relic Collector
# Author: Russ Shouldice
# Creation Date: June 24, 2015
#
# Description: framework functionality to support remote collector
#
#
# Change Logs
#      June 24, 2015.     v1.0
#
#
#
#



""
"=== Relic Collector - v1.0 === "
"Scans servers for maintenance related statistics and saves to JSON file."
""

# Check for config file
#$inputFile = ".\computers.ini"
#if (-not (Test-Path $inputFile)) {
#    "Script failure: computers.ini file not found."
#    "Please create this file with 1 hostname per line."
#    ""
#    Cmd /c pause
#    Exit
#}

# Check for config file
$inputFile = ".\config.ini"
if (-not (Test-Path $inputFile)) {
    "Script failure: config.ini file not found."
    "Please create this with the following syntax:"
    ""
    "[Config]"
    "client=< name of your client >"
    "hosts=< comma separated list of hostnames >"
    ""
    "For a complete list of client names please see http://c3po.kidsability.local/relicdev/api/collect/clients/"
    ""
    Cmd /c timeout /t 1
    Exit
}

# Get the config parameters and stick it into a PowerShell object
Get-Content "config.ini" | foreach-object -begin {$config=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $config.Add($k[0], $k[1]) } }

# Set parameters to handy variable names
$client = $config.client
$hosts = $config.hosts.split(',')
$url = $config.url
$masterTimer = $config.mastertimer
$user = [Environment]::UserName


#
# getStorageStats function.
#     Accepts the hostname of computer to check.
#     Returns a PowerShell object containing the clientname, hostname, and storage stats.
#
Function getStorageStats($hostname) {
    # Put the value of $computer into $c.
    #$c = $computer

    # Create an OS object and check if it works.
    # If the object cannot be created silently continue and save a message to the CSV file.
    $exist = Get-WmiObject win32_operatingsystem -ComputerName $hostname -errorAction silentlyContinue

    if ($exist) {
        #Get the logical disk object for this computer
        $disks = Get-WmiObject win32_logicaldisk -computername $hostname

        #initialize disk string variables
        $d2Free = -1
        $d2Size = -1
        $d3Free = -1
        $d3Size = -1
        [String]$d1 = ","
        [String]$d2 = ","
        [String]$d3 = ","
        [String]$d1ssf = ""
        [String]$d2ssf = ""
        [String]$d3ssf = ""     

        #Check each variable in the array disks
        Foreach ($d in $disks) {           
            #Get C drive stats, then check for the presence of other drives
            If ($d.DeviceID -eq "C:") {
                [Long]$d1Free = $d.FreeSpace / 1GB - 1
                [Long]$d1Size = $d.Size / 1GB - 1
                $d1 = [String]$d1Free + "," + $d1Size
                $d1ssf = "C: " + $d1Free + "GB/" + $d1Size + "GB"
            } elseif ($d.DeviceID -eq "D:" -and $d.DriveType -eq 3) {
                [Long]$d2Free = $d.FreeSpace / 1GB - 1
                [Long]$d2Size = $d.Size / 1GB - 1
                $d2 = [String]$d2Free + "," + $d2Size
                $d2ssf = ", D: " + $d2Free + "GB/" + $d2Size + "GB"
            } elseif ($d.DeviceID -eq "E:" -and $d.DriveType -eq 3) {
                [Long]$d3Free = $d.FreeSpace / 1GB - 1
                [Long]$d3Size = $d.Size / 1GB - 1
                $d3 = [String]$d3Free + "," + $d3Size
                $d3ssf = ", E: " + $d3Free + "GB/" + $d3Size + "GB"
            }
        }      
                  
        # Collate the info into a PowerShell object
        $storageObject = @{ client=[String]$client;
                            hostname=[String]$hostname;
                            d1size=[String]$d1Size;
                            d1free=[String]$d1Free;
                            d2size=[String]$d2Size;
                            d2free=[String]$d2Free;
                            d3size=[String]$d3Size;
                            d3free=[String]$d3Free
                        }

        #return the PowerShell object
        Return $storageObject

    } else {
        $status = "     " + $c + " was not found or did not respond.  PC record skipped"
        $status
        #$c + " not found..."
        continue
    }
}






<#
    getVSSStats function.
        $cname: must be a hostname of the computer to check
        Returns comma separated set of two stats: status and count.
#>
function getVSSStats($hostname) {
    # initalize the $sum variable.
    $sum = 0

    # Get high level VSS status info
    $vss = Get-WmiObject Win32_Service -ComputerName $hostname -Filter 'Name="VSS"' | Select-Object *

    # If VSS is running on the computer, then get the number of shadow copies, otherwise $sum is 0.
    if ($vss.state -eq "Running") {
        $count = Get-WmiObject -Class Win32_ShadowCopy -ComputerName $hostname | Select-Object -Property Count | Measure-Object Count -sum
        $sum = [int]$count.sum
    }

    # Collate info into powershell object
    $vssObject = @{
                    client=$client;
                    hostname=$hostname;
                    vssState=$vss.state;
                    vssShareCount=[String]$sum
    }
    
    # Return powershell object
    return $vssObject
}








# Main loop on a timer
while ($true) {  
    # reset the comma, date, and status
    $date = Get-Date
    "Start stats gathering loop.  " + $date
    #$comma = ','
    #$status = ""

    $x = 1
    # for each computer in the list of computers
    Foreach ($h in $hosts) {
        "Getting stats for: " + $h + "; record " + $x + " of " + $hosts.Length
           
        # get the storage stats and file it in the database
        $storageStats = getStorageStats($h)
        $json = $storageStats | ConvertTo-Json
        $storageUrl = $url + "/storage"
        # send it to the server.
        Invoke-RestMethod -Uri $storageUrl -Method Post -Body $json -ContentType 'application/json'
        
        # get volume shadow copy stats and file it in to the database
        $vssStats = getVSSStats($h)
        $json = $vssStats | ConvertTo-Json
        $vssUrl = $url + "/vss"
        # send it to the server.
        Invoke-RestMethod -Uri $vssUrl -Method Post -Body $json -ContentType 'application/json'
        
        # increment the counter
        $x = $x + 1
    }


    #Sleep for the number of second specified by the $masterTimer
    Start-Sleep $masterTimer
}


