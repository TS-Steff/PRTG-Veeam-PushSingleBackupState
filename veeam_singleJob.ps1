<#

    .SYNOPSIS
    PRTG push Veeam Single Job Status
    
    .DESCRIPTION
    Advanced Sensor will report Result of last job
    
    .EXAMPLE
    veeam_singleJob.ps1 -JobName "Data to Cloud Repository"

    .EXAMPLE
    veeam_singleJob.ps1 -JobName "Data to Cloud Repository" -DryRun
    
    .NOTES
    ┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
    │ ORIGIN STORY                                                                                │ 
    ├─────────────────────────────────────────────────────────────────────────────────────────────┤ 
    │   DATE        : 2022.03.02                                                                  |
    │   AUTHOR      : TS-Management GmbH, Stefan Müller                                           | 
    │   DESCRIPTION : PRTG Push Veeam Backup State                                                |
    └─────────────────────────────────────────────────────────────────────────────────────────────┘

    .Link
    https://ts-man.ch
#>
[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$true)] # true
        [string]$JobName = "jobName",
	[Parameter(Position=1, Mandatory=$false)]
		[switch]$DryRun = $false               # false
)


##### COFNIG START #####
$probeIP = "PRTG HOST"  #include https or http
$sensorPort = "PORT"
$sensorKey ="KEY"
#####  CONFIG END  #####

#Make sure PSModulePath includes Veeam Console
$MyModulePath = "C:\Program Files\Veeam\Backup and Replication\Console\"
$env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$MyModulePath"
if ($Modules = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell){
    try {
        $Modules | Import-Module -WarningAction SilentlyContinue
    }catch{
        throw "Failed to load Veeam Modules"
    }
}


# check if veeam powershell snapin is loaded. if not, load it
if( (Get-PSSnapin -Name veeampssnapin -ErrorAction SilentlyContinue) -eq $nul){
    Add-PSSnapin veeampssnapin -ErrorAction SilentlyContinue
}

# if the script is run at the end of a job, the status is unknown. Therefore a delay is needed.
#sleep -Seconds 90

### Get the Job ###
$job = Get-VBRJob -Name $JobName

if(-not $job){
    write-error "no job" 
    exit
}


### Job exists get last session and info ###
$lastSession = $job.FindLastSession()

if($DryRun){
    write-host $job.Name
    write-host "**LAST SESSION**"
    write-host "lastSession is Completed: " $lastSession.IsCompleted
    write-host "Job Name: " $lastSession.Name
    write-host "Start: " $lastSession.CreationTime
    write-host "End: " $lastSession.EndTime
    write-host "Duration: " $lastSession.Progress.Duration
    write-host "Result: " $lastSession.Result
    write-host ""
}


$jobCompleted = $lastSession.IsCompleted
$jobLastStart = $lastSession.CreationTime.DateTime
$jobDuration = $lastSession.Progress.Duration.TotalSeconds
$jobResult = $lastSession.Result

$timeNow = Get-Date
$date_diff = New-TimeSpan -Start $lastSession.EndTime -End $timeNow
$jobHoursSinceLastRun = $date_diff.TotalHours


switch($jobResult){
    "Success" { $jobResultCode = 0 } # OK
    "Warning" { $jobResultCode = 1 } # Warning
    "Failed"  { $jobResultCode = 2 } # Error
    Default   { $jobResultcode = 9 } # Unknown
}

if($jobResultCode -eq 9){
    if($job.GetLastState() -eq "Working"){
        $jobResultCode = 8
    }elseif($job.GetLastState() -eq "Stopping"){
        $jobResultCode = 7
    }elseif($job.GetLastState() -eq "Postprocessing"){
        $jobResultCode = 6
    }
}

### PRTG XML Header ###
$prtgresult = @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>

"@


### PRTG RESULT XML###
$prtgresult += @"
  <text>$JobName | $jobLastStart</text>
  <result>
    <channel>Result</channel>
    <unit>Custom</unit>
    <value>$jobResultCode</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
    <ValueLookup>ts.veeam.jobstatus.push</ValueLookup>
  </result>
  <result>
    <channel>Completed</channel>
    <unit>Custom</unit>
    <value>$jobCompleted</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
  </result>
  <result>
    <channel>Duration</channel>
    <unit>TimeSeconds</unit>
    <value>$jobDuration</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
  </result>
  <result>
    <channel>Hours since last run</channel>
    <unit>TimeHours</unit>
    <value>$([int]($jobHoursSinceLastRun))</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
  </result>
"@


### PRTG XML Footer ###
$prtgresult += @"

</prtg>
"@

#write-host $prtgresult

function sendPush(){
    Add-Type -AssemblyName system.web

    write-host "result"-ForegroundColor Green
    write-host $prtgresult 

    #$Answer = Invoke-WebRequest -Uri $NETXNUA -Method Post -Body $RequestBody -ContentType $ContentType -UseBasicParsing
    $answer = Invoke-WebRequest `
       -method POST `
       -URI ($probeIP + ":" + $sensorPort + "/" + $sensorKey) `
       -ContentType "text/xml" `
       -Body $prtgresult `
       -usebasicparsing

    if ($answer.statuscode -ne 200) {
       write-warning "Request to PRTG failed"
       write-host "answer: " $answer.statuscode
       exit 1
    }
    else {
       $answer.content
    }
}

if($DryRun){
    write-host $prtgresult
}else{
    sendPush
}
