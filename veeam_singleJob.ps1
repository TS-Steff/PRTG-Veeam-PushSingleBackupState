<#
.NOTES
┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
│ ORIGIN STORY                                                                                │ 
├─────────────────────────────────────────────────────────────────────────────────────────────┤ 
│   DATE        : 2022.03.02                                                                  |
│   AUTHOR      : TS-Management GmbH, Stefan Müller                                           | 
│   DESCRIPTION : PRTG Push Veeam Backup State                                                |
└─────────────────────────────────────────────────────────────────────────────────────────────┘

"SRV-01 - Daten to Cloud"
#>
[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$true)]
        [string] $JobName = "asdf"
)

##### COFNIG START #####
$probeIP = "PROBE"
$sensorPort = "PORT"
$sensorKey ="KEY"
#####  CONFIG END  #####

### Get the Job ###
$job = Get-VBRJob -Name $JobName

if(-not $job){
    write-error "no job" 
    exit
}


### Job exists get last session and info ###
$lastSession = $job.FindLastSession()


#write-host $job.Name
#write-host "**LAST SESSION**"
$jobCompleted = $lastSession.IsCompleted
#write-host "lastSession is Completed: " $lastSession.IsCompleted
#write-host "Job Name: " $lastSession.Name

#write-host "Start: " $lastSession.CreationTime
#write-host "End: " $lastSession.EndTime

$jobDuration = $lastSession.Progress.Duration.TotalSeconds
#write-host "Duration: " $lastSession.Progress.Duration

$jobResult = $lastSession.Result
#write-host "Result: " $lastSession.Result

switch($jobResult){
    "Success" { $jobResultCode = 0 } # OK
    "Warning" { $jobResultCode = 1 } # Warning
    "Failed"  { $jobResultCode = 2 } # Error
    Default   { $jobResultcode = 9 } # Unknown
}


### PRTG XML Header ###
$prtgresult = @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>
"@


### PRTG RESULT XML###
$prtgresult += @"
  <text>$JobName</text>
  <result>
    <channel>Result</channel>
    <unit>Custom</unit>
    <value>$jobResultCode</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
  </result>
  <result>
    <channel>Completed</channel>
    <unit>Custom</unit>
    <value>$jobCompleted</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
  </result
  <result>
    <channel>Duration</channel>
    <unit>TimeSeconds</unit>
    <value>$jobDuration</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
  </result>
"@


### PRTG XML Footer ###
$prtgresult += @"
</prtg>
"@


write-host $prtgresult





function sendPush(){
    Add-Type -AssemblyName system.web

    write-host "result"-ForegroundColor Green
    write-host $prtgresult 

    #$Answer = Invoke-WebRequest -Uri $NETXNUA -Method Post -Body $RequestBody -ContentType $ContentType -UseBasicParsing
    $answer = Invoke-WebRequest `
       -method POST `
       -URI ("http://" + $probeIP + ":" + $sensorPort + "/" + $sensorKey) `
       -ContentType "text/xml" `
       -Body $prtgresult `
       -usebasicparsing

       #-Body ("content="+[System.Web.HttpUtility]::UrlEncode.($prtgresult)) `
    #http://prtg.ts-man.ch:5055/637D334C-DCD5-49E3-94CA-CE12ABB184C3?content=<prtg><result><channel>MyChannel</channel><value>10</value></result><text>this%20is%20a%20message</text></prtg>   
    if ($answer.statuscode -ne 200) {
       write-warning "Request to PRTG failed"
       write-host "answer: " $answer.statuscode
       exit 1
    }
    else {
       $answer.content
    }
}

sendPush
