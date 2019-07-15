

$PodStartTime = Get-Date

Import-Module PowerShellGet
Install-Module -Name Az.Accounts -Force -Verbose
Install-Module -Name Az.Compute -Force -Verbose
Install-Module -Name Az.Resources -Force -Verbose
Install-Module -Name Az.Storage -Force -Verbose
Import-Module Az.Accounts
Import-Module Az.Compute
Import-Module Az.Storage
Import-Module Az.Resources
$error | out-file /scripts/logs.txt -append
$CronJobStartTime = Get-Date
$containerName = "reports" #for blob
$CurrentBatch = (get-childitem env: | where {$_.Name -like "*batch*"}| Select Name).Name
#########################################
$vstspat = get-content /etc/vsts-pat/vstspat
$servicePrincipalClientId = get-content /etc/dacreds/servicePrincipalClientId
$servicePrincipalClientSecret = get-content /etc/dacreds/servicePrincipalClientSecret
$EmailUserName = Get-Content "/etc/emailcredentials/emailusername"
$EmailPassword = Get-Content "/etc/emailcredentials/emailpassword"
$user="gopinath.thiruvengadam@trgc.com"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$vstspat)))
$SecurePassword=convertto-securestring -AsPlainText -Force -String $EmailPassword
$O365creds = New-object -TypeName System.Management.Automation.PSCredential -ArgumentList ($EmailUserName,$SecurePassword) 
#Be careful with the hyphen if you are reusing the above!!!  -- https://stackoverflow.com/questions/45863545/new-object-pscredential-not-working-using-unicode-punctuation-syntactically Welcome to Linux(or blame it Linux)
#Connecto to Azure
$clientID = "$servicePrincipalClientId"
$passwd = "$servicePrincipalClientSecret"
$tenantID = "28743320-645e-4840-8154-b4babd41162c"
$secpasswd = ConvertTo-SecureString  -AsPlainText -Force -string $passwd
$pscredential = New-Object System.Management.Automation.PSCredential($clientID, $secpasswd)
Connect-AzAccount -ServicePrincipal -Credential $pscredential -TenantId $tenantId
###########################################

Select-AzSubscription -SubscriptionName "LAB01-TRG01"
Set-AzCurrentStorageAccount -StorageAccountName saaksdemo -ResourceGroupName  RG-TRG01-LAB01-GOPI
$ConsolidatedReport = @()
$csv = Import-CSV "/scripts/InputCSV.csv" | where {$_.batch -eq "$CurrentBatch"}

$allcsv = Import-CSV "/scripts/InputCSV.csv" 
[int]$NumberofBatches = ($allcsv | Select-Object Batch -Unique|Measure-Object).Count

#>
Function HTMLHeader4Reports
{
    $ReportTitle = $args[0]
    $header = "
            <html>
            <head>
            <meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
            <title>$ReportTitle</title>
            <STYLE TYPE='text/css'>
            <!--
            td {
                font-family: Tahoma;
                font-size: 11px;
                border-top: 1px solid #999999;
                border-right: 1px solid #999999;
                border-bottom: 1px solid #999999;
                border-left: 1px solid #999999;
                padding-top: 0px;
                padding-right: 0px;
                padding-bottom: 0px;
                padding-left: 0px;
            }
            body {
                margin-left: 5px;
                margin-top: 5px;
                margin-right: 0px;
                margin-bottom: 10px;
                table {
                border: thin solid #000000;
            }
            -->
            </style>
            </head>
            <body>
            <table width='100%'>
            <tr bgcolor='#CCCCCC'>
            <td colspan='7' height='25' align='center'>
            <font face='tahoma' color='#003399' size='4'><strong>$ReportTitle </strong></font>
            </td>
            </tr>
            </table>
    "
    Return $header
}

Function TableHeader4Reports 
{
    $argumentsCount = ($args |Measure-Object).Count
    $newline = "`n"
    $HeaderPrefix = "
    <table width='100%'><tbody>
        <tr bgcolor=#CCCCCC>"

    Foreach($arguments in $args)
    {
    [string]$ValueRows+= "<td width='10%' align='center'>$arguments</td>"+$newline
    }

    $BottomHeader = "</tr>"


    $FullTableHeader = $HeaderPrefix+$newline+$ValueRows+$BottomHeader


    Return $FullTableHeader
}
Function ReportingItems()
{
    #Set colors for table cell backgrounds
    $redColor = "#FF0000"
    $greenColor = "#01DF3A"
    $orangeColor = "#FBB917"
    $whiteColor = "#FFFFFF"
    Set-Location scripts
    [string]$HtmlReportFileName= "azDevops_ScaleDownReport_$(get-date -format MM-dd-yyyy).html"
    [string]$LogsPath="azDevops_ScaleDownLogs_$(get-date -format MM-dd-yyyy).txt"
    [string]$htmlblobName="scripts/reports/"+$HtmlReportFileName
    [string]$logsblobName="scripts/Logs/"+$LogsPath
    [string]$HeadingofReport="Azure Report - AZ Resource Scale Down Report"

    #We are using the method of sending the parameters are arguments, using hashtable in used later in the script.
    $HTMLTitleoutput = HTMLHeader4Reports  $HeadingofReport
    $ColumnNameOutput = TableHeader4Reports VMName resourceGroup CurrentBatch ScaleOperationStartTime_EST ScaleOperationEndTime_EST NormalVMSize CurrentVMSize ScaleDownSize VMScaleDownWindowTime ScaleOperation AzVMStatusCode IsDaylightSavingTime ScaleOperationResult
    #The log file and the html file has to exist before I can add content to it.
    New-Item -ItemType File -Name $HtmlReportFileName # creates in c:\temp
    New-Item -ItemType File -Name $LogsPath
    Add-Content $HtmlReportFileName $HTMLTitleoutput # this is thoe first row of the report containing the Title
    Add-Content $HtmlReportFileName $ColumnNameOutput # this is the second row of the report containing the headers
}
ReportingItems
Function SendEmail($EmailParameters)
{    
    $body = Get-Content $HtmlReportFileName -Raw
    Send-MailMessage -To $EmailParameters.ToAddress `
        -Subject $EmailParameters.MessageSubject  `
        -UseSsl -Port 587 -Body $body -SmtpServer 'smtp.office365.com' `
        -From $EmailParameters.FromAddress  -BodyAsHtml -Credential $O365creds
 }

##################
[hashtable]$EmailParameters = @{"FromAddress"="TRGO365SupportToolDev@trgc.com"; `
"ToAddress"="TRGAzureReports@trgc.com";"MessageSubject"="Azure Report - AZ Resource Scale Down Report"; `
"HtmlBlobName"="$htmlblobName";"Container"=$Container;"LogsBlobName"=$LogsblobName}

[string]$IsDaylightSavingTime = (Get-Date).IsDaylightSavingTime() # wonder why but from the pod it returns false in summer, although from Windows 10 its TRUE in summer.

[string]$IsDaylightSavingTime  |  out-file /scripts/logs.txt -append
#Even if someone runs this pod during business hours, it should not anything. This should strictly run after business hours only.

if($IsDaylightSavingTime -eq "False")
{
    $WhatTimeoftheDayisit = ((Get-Date).ToUniversalTime()).addhours(-4).Hour # in EST adjusting for daylight savings time.
    $WhatDayofWeekisit = ((Get-Date).ToUniversalTime()).addhours(-4).DayofWeek
}
elseif($IsDaylightSavingTime -eq "True")
{
    $WhatTimeoftheDayisit = ((Get-Date).ToUniversalTime()).addhours(-5).Hour # in EST adjusting for daylight savings time.
    $WhatDayofWeekisit = ((Get-Date).ToUniversalTime()).addhours(-4).DayofWeek
}

Function GetScaleOperationvar($WeekDaysOffBusinessHoursWindowStart, $WeekDaysOffBusinessHoursWindowEnd)
{
    
    Switch($WhatDayofWeekisit)
    {
            "Sunday"
            {
                if ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowEnd") 
                {
                    $ScaleOperation = "ScaleUP"
                    #should be 23 -- scaleUP
                }
            }
            "Monday"
            {
                #weekdays scale down starts at 6 pm EST, and we are giving a buffer of 1 hour for the job to start.
                #if the job is called after 7 pm EST, something isnt working as expected.
                if ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowStart")
                {
                    $ScaleOperation = "ScaleDown"
                }
                elseif ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowEnd")
                {
                    $ScaleOperation = "ScaleUP"
                }
            }
            "Tuesday"
            {
                #weekdays scale down starts at 6 pm EST, and we are giving a buffer of 1 hour for the job to start.
                #if the job is called after 7 pm EST, something isnt working as expected.
                if ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowStart")
                {
                    $ScaleOperation = "ScaleDown"
                }
                elseif ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowEnd")
                {
                    $ScaleOperation = "ScaleUP"
                }
            }
            "Wednesday"
            {
                #weekdays scale down starts at 6 pm EST, and we are giving a buffer of 1 hour for the job to start.
                #if the job is called after 7 pm EST, something isnt working as expected.
                if ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowStart")
                {
                    $ScaleOperation = "ScaleDown"
                }
                elseif ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowEnd")
                {
                    $ScaleOperation = "ScaleUP"
                }
            }
            "Thursday"
            {
                #weekdays scale down starts at 6 pm EST, and we are giving a buffer of 1 hour for the job to start.
                #if the job is called after 7 pm EST, something isnt working as expected.
                if ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowStart")
                {
                    $ScaleOperation = "ScaleDown"
                }
                elseif ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowEnd")
                {
                    $ScaleOperation = "ScaleUP"
                }
            }
            "Friday"
            {
                #weekdays scale down starts at 6 pm EST, and we are giving a buffer of 1 hour for the job to start.
                #if the job is called after 7 pm EST, something isnt working as expected.
                if ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowStart")
                {
                    $ScaleOperation = "ScaleDown"
                }
                elseif ($WhatTimeoftheDayisit -eq "$WeekDaysOffBusinessHoursWindowEnd")
                {
                    $ScaleOperation = "ScaleUP" #only for troubleshooting
                }
            }
            "Saturday"
            {
                $ScaleOperation = "NONE"
            }       
    }

    Return $ScaleOperation
}
"Just before entering big FOR each row." | Out-File /scripts/logs.txt -append
$error | Out-File /scripts/logs.txt -append

$FinalReport = @()
Foreach($row in $csv)
{
    $error | Out-File /scripts/logs.txt -append
    $error.Clear()
    [string]$resourceGroup = "";[string]$VMName = "";[string]$ScaleDownSize = ""
    [string]$ScaleUPSize = "";[string]$NormalVMSize = "";[string]$WeekDaysOffBusinessHoursWindowStart
    [string]$WeekDaysOffBusinessHoursWindowEnd="";[string]$VMScaleWindow="";[string]$ScaleOperation
        if($IsDaylightSavingTime -eq "False")
        {
            $ScaleOperationStart = ((Get-Date).ToUniversalTime()).addhours(-4)
        }
        else
        {
            $ScaleOperationStart = ((Get-Date).ToUniversalTime()).addhours(-5)
        }
        $WeekDaysOffBusinessHoursWindowStart = $row.WeekDaysOffBusinessHoursWindowStart
        $WeekDaysOffBusinessHoursWindowEnd   = $row.WeekDaysOffBusinessHoursWindowEnd       
        $VMScaleDownWindowTime =   "$WeekDaysOffBusinessHoursWindowStart" + ":00 - " + $WeekDaysOffBusinessHoursWindowEnd + ":00"
        $ScaleOperation = GetScaleOperationvar $WeekDaysOffBusinessHoursWindowStart $WeekDaysOffBusinessHoursWindowEnd 
        $VMScaleWindow = "$WeekDaysOffBusinessHoursWindowStart" + ":00 - " + "$WeekDaysOffBusinessHoursWindowEnd" + ":00"
        #Get VM details from csv
        [string]$resourceGroup = $row.ResourceGroupName
        [string]$VMName = $row.VMName
        [string]$ScaleDownSize = $row.OffBusinessHoursVMSize
        [string]$ScaleUPSize = $row.BusinessHoursSize
        [string]$NormalVMSize = $row.BusinessHoursSize
        $vm = Get-AzVM -ResourceGroupName $resourceGroup -VMName $vmName
        $vm | out-file /scripts/logs.txt -append
        
        if($ScaleOperation -eq "ScaleDown" -or $ScaleOperation -eq "ScaleUP")
        {
            #do nothing
            "I am inside if -- $ScaleOperation"  | out-file /scripts/logs.txt -append
        }
        Else
        {
            $ScaleOperation = "None"
            "I am inside  else  -- $ScaleOperation"  | out-file /scripts/logs.txt -append
        }
        #Override scale operation variable based on resource tag {RlgyScaleOption: "TRUE"} | {RlgyScaleOption: "FALSE"} 
        #False means BU doesnt want to touch this VM, and let it run at full capacity at all times.

        [string]$RlgyScaleOption = (Get-AzResource -Name "$VMName" -ResourceGroupName "$resourceGroup").Tags.RlgyScaleOption
        if($RlgyScaleOption -eq "FALSE")
        {
            $ScaleOperation = "BUOverRide"
            "I am inside RlgyScaleOption if -- $RlgyScaleOption"  | out-file /scripts/logs.txt -append
        }
        Switch($ScaleOperation)
        {
            "None"
            {
                $CurrentVMSize = (get-azvm -Name "$VMName" -ResourceGroupName $resourceGroup | Select-Object HardwareProfile).HardwareProfile.VmSize
                $ScaleOperationResult = "VM was untouched, but job shouldnt have run at this time though!"
                $ScaleOperation| out-file /scripts/logs.txt -append
                $BGColor8 = "$REDCOLOR"
                $BGColor9 = "$REDCOLOR"
            }
            "ScaleDown"
            {
                $error | Out-File /scripts/logs.txt -append #dump errors to log file. 
                $error.Clear() #reset errors.
                $ScaleOperation| out-file /scripts/logs.txt -append
                "Inside Switch -- ScaleDown -- $ScaleDownSize"  | out-file /scripts/logs.txt -append
                $vm.HardwareProfile.VmSize = "$ScaleDownSize"
                Update-AzVM -VM $vm -ResourceGroupName $resourceGroup
                "what is the value below there should be no errors--$VMName" | Out-File /scripts/logs.txt -append
                "============================" | Out-File /scripts/logs.txt -append
                $error | Out-File /scripts/logs.txt -append #dump errors to log file. 
                "============================" | Out-File /scripts/logs.txt -append
                
                "what is the value above there should be no errors" | Out-File /scripts/logs.txt -append
                ($Error|Measure-Object).Count  | Out-File /scripts/logs.txt -append
                #look for any errors
                if(($Error|Measure-Object).Count -eq "0")
                    {
                            $ScaleOperationResult = "OK"
                            $BGColor12 ="$greencolor"
                    }  
                  else
                    {
                        $ScaleOperationResult = "Errors were found - $Error"
                        $BGColor12 ="$redcolor"
                    }
            }
            "ScaleUP"
            {
                $error | Out-File /scripts/logs.txt -append #dump errors to log file.
                $error.Clear() #reset errors.
                $ScaleOperation| out-file /scripts/logs.txt -append
                $vm.HardwareProfile.VmSize = "$ScaleUPSize"
                "Inside Switch -- ScaleUP -- $ScaleUPSize"  | out-file /scripts/logs.txt -append
                Update-AzVM -VM $vm -ResourceGroupName $resourceGroup
                 "what is the value below there should be no errors--$VMName" | Out-File /scripts/logs.txt -append
                "============================" | Out-File /scripts/logs.txt -append
                $error | Out-File /scripts/logs.txt -append #dump errors to log file. 
                "============================" | Out-File /scripts/logs.txt -append
                
                "what is the value above there should be no errors" | Out-File /scripts/logs.txt -append
               
                #look for any errors
                if(($Error|Measure-Object).Count -eq "0")
                    {
                            $ScaleOperationResult = "OK"
                            $BGColor12 ="$greencolor"
                    }  
                  else
                    {
                        $ScaleOperationResult = "Errors were found- $VMName - $Error"
                        $BGColor12 ="$redcolor"
                    }
            }
            "BUOverRide"
            {
                $ScaleOperationResult = "NA - BU has set scale option as FALSE - No action taken at this time."
                $ScaleOperationResult  | out-file /scripts/logs.txt -append
                $BGColor6 = "$ORANGECOLOR"
                $BGColor7 = "$ORANGECOLOR"
                $BGColor8 = "$ORANGECOLOR"
                $BGColor9 = "$ORANGECOLOR"
                $ScaleDownSize = "N/A"
            }
        }
        
        #Calculate the time scale operation completed.
        if($IsDaylightSavingTime -eq "False")
        {
            $ScaleOperationEnd = ((Get-Date).ToUniversalTime()).addhours(-4)
        }
        else
        {
            $ScaleOperationEnd = ((Get-Date).ToUniversalTime()).addhours(-5)
        }      
        [string]$CurrentVMSize = (Get-Azvm -VMName "$VMName" -ResourceGroupName $resourceGroup  | Select-Object HardwareProfile).HardwareProfile.VmSize
        [string]$AzVMStatusCode = (Get-Azvm -VMName $VMName -ResourceGroupName $resourceGroup | Select StatusCode).StatusCode

        if($AzVMStatusCode -eq "OK")
        {
            $BGColor10 = "$greenColor"
        }
        else 
        {
            $BGColor10 = "$redColor"    
        }
      
        $Object = New-Object PSObject
        $Object | add-member Noteproperty VMName $VMName
        $Object | add-member Noteproperty resourceGroup $resourceGroup
        $Object | add-member Noteproperty CurrentBatch $CurrentBatch
        $Object | add-member Noteproperty ScaleOperationStart $ScaleOperationStart
        $Object | add-member Noteproperty ScaleOperationEnd $ScaleOperationEnd
        $Object | add-member Noteproperty NormalVMSize $NormalVMSize
        $Object | add-member Noteproperty CurrentVMSize $CurrentVMSize
        $Object | add-member Noteproperty ScaleDownSize $ScaleDownSize
        $Object | add-member Noteproperty VMScaleWindow $VMScaleDownWindowTime
        $Object | add-member Noteproperty ScaleOperation $ScaleOperation
        $Object | add-member Noteproperty AzVMStatusCode $AzVMStatusCode
        $Object | add-member Noteproperty IsDaylightSavingTime $IsDaylightSavingTime
        $Object | add-member Noteproperty ScaleOperationResult $ScaleOperationResult
        $FinalReport += $Object
        #Add-Content $HtmlReportFileName $dataRow; # third row(and fourth row for each value in the array) of the report adding values
        $BGColor6 = $BGColor7 = $BGColor8 = $BGColor9 = "" #reset 

}
#$FinalReport | out-file /scripts/logs.txt -append
$FinalReport | export-csv /scripts/finalreport.csv -notypeinformation  
#Only the master pod -- the pod that has the variable value of $env:batch1 set
#The master pod will need to ensure that all the batches have been completed and then send the consolidated report.
Function CheckifAllBatchesareComplete()
{
    [int]$timetowait = 30
    
            Select-AzSubscription -SubscriptionName "LAB01-TRG01" | Out-Null #if I dont suppress the output its tagging along on RETURN!
            "-------CheckifAllBatchesareComplete--$NumberofBatches-$$NumberofBatches-->>>>>>" | out-file /scripts/logs.txt -append
            Set-AzCurrentStorageAccount -StorageAccountName saaksdemo -ResourceGroupName  RG-TRG01-LAB01-GOPI
    do
    {
        $ConsolidatedReport =@() #if do is repeated then reset this or there could be duplicates.
        $AllPodsDone = @()
        For($k=2; $k -le $NumberofBatches; $k++)
        {
            #if you are the master node, download the reports from blob.
            $CurrArr = @()            
            $ReportFileName = "_report.csv"
            [string]$blobName = "batch" + "$k" + $ReportFileName
            "-------blobName----$blobName->>>>>>" | out-file /scripts/logs.txt -append
            [string]$currBlobCount = (Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Force -ErrorAction "SilentlyContinue" | Measure-Object).Count
            if($currBlobCount -eq 0)
            {
                $AllPodsDone += "FALSE"
                "-------AllPodsDone----$AllPodsDone->>>>>>" | out-file /scripts/logs.txt -append                     
                $timetowait-=1          
                "-------timetowait----$timetowait->>>>>>" | out-file /scripts/logs.txt -append
            }
            Else
            {
                $AllPodsDone += "MAYBE"
                $CurrArr = Import-CSV $blobName
                $ConsolidatedReport += $CurrArr
                "-------AllPodsDone----$AllPodsDone->>>>>>" | out-file /scripts/logs.txt -append
                "-------CurrArr----$CurrArr->>>>>>" | out-file /scripts/logs.txt -append
                "-------ConsolidatedReport----$ConsolidatedReport->>>>>>" | out-file /scripts/logs.txt -append
            }    
        }
        #If one full loop has reported that all files exist, then its time to quit Do-While.
        if($AllPodsDone -contains "FALSE")
        {
            [string]$AllPodsDoneBool = "FALSE"
        }
        else 
        {
            [string]$AllPodsDoneBool = "TRUE"
        }
        start-sleep -s 60  #sleep before checking again.    
    }while($AllPodsDoneBool -eq "FALSE" -and $TimetoWait -lt "30")
    
    Return $ConsolidatedReport
}
Function TriggerBuild()
{
        $body = '
        { 
                "definition": {"ID": 684} 
        }
        '
        $bodyJson=$body | ConvertFrom-Json
        Write-Output $bodyJson
        $bodyString=$bodyJson | ConvertTo-Json -Depth 100
        Write-Output $bodyString
        
        $Uri = "https://dev.azure.com/realogy/O365CSTool.TRG/_apis/build/builds?api-version=5.0"
        $buildresponse = Invoke-RestMethod -Method Post -UseDefaultCredentials -ContentType application/json -Uri $Uri -Body $bodyString -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
        $Status = (Invoke-RestMethod -Method Get -UseDefaultCredentials -ContentType application/json -Uri $buildresponse.URL -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}).Status
        [int]$timelefttowait  = "15" #15 minutes
        Do
        {
            $Status = (Invoke-RestMethod -Method Get -UseDefaultCredentials -ContentType application/json -Uri $buildresponse.URL -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}).Status
            $timelefttowait= ($timelefttowait - 1)
            Write-Output "Status is $Status -- $timelefttowait"
            "Status is $Status --time to wait -- $timelefttowait" | out-file /scripts/logs.txt -append
            Start-Sleep -s 60
            #This loop will never complete as TFS would have deleted the deployment while this pod is waiting for TFS job to complete.
        }While($Status -ne 'completed' -and $timelefttowait -ne '0')
        Return $buildresponse 
}
Function CleanupBlobs_KillAllDeployments($ConsolidatedReport)
{
    
   #Delete the blob files created by slave pods. 
   "inside FN CleanupBlobs_KillAllDeployments" | Out-File /scripts/logs.txt -append
   "ConsolidatedReport -- $ConsolidatedReport" | Out-File /scripts/logs.txt -append
   #second condition is to remove a blank line at the end.
   $currbatches = ($ConsolidatedReport | Select-Object CurrentBatch -Unique | where {$_.CurrentBatch -ne "batch1" -and $_.CurrentBatch -like "*batch*"}).CurrentBatch
   "currbatches --$currbatches" | Out-File /scripts/logs.txt -append
   Foreach($batch in $currbatches)
   {
       [string]$blobfullname = $batch + "_report.csv"
       Remove-AzStorageBlob -Container "$containerName" -Blob "$blobfullname" -Force
       "containerName -- $containerName -- blobfullname - $blobfullname" | Out-File /scripts/logs.txt -append
   }
   
   $buildresponse = TriggerBuild
}
Function UploadReporttoBlob($CurrentBatch)
{
    $ReportFileName = "_report.csv"
    [string]$blobName =  $CurrentBatch + $ReportFileName
    Select-AzSubscription -SubscriptionName "LAB01-TRG01"
    Set-AzCurrentStorageAccount -StorageAccountName saaksdemo -ResourceGroupName  RG-TRG01-LAB01-GOPI

    Set-AzStorageBlobContent -Blob $blobName -Container $containerName -File "/scripts/finalreport.csv" -Force
}
"-------CurrentBatch--$CurrentBatch--->>>>>>" | out-file /scripts/logs.txt -append
if($CurrentBatch -eq "batch1")
{
    $ConsolidatedReport = CheckifAllBatchesareComplete
    "-------consolidate report is below----->>>>>>" | out-file /scripts/logs.txt -append
    $ConsolidatedReport | out-file /scripts/logs.txt -append
    "-------ConsolidatedReport count is below----->>>>>>" | out-file /scripts/logs.txt -append
    $ConsolidatedReport | Measure
    $ConsolidatedReport += $FinalReport
    $ConsolidatedReport = $ConsolidatedReport |Sort-Object CurrentBatch # sort it.
    $ConsolidatedReport = $ConsolidatedReport[0..(($ConsolidatedReport|Measure-Object).Count-2)] #remove the last row, its blank for some reason.
    Foreach($line in $ConsolidatedReport)
    {
        $VMName =$line.VMName 
        $resourceGroup = $line.resourceGroup
        $CurrentBatch = $line.CurrentBatch
        $ScaleOperationStart = $line.ScaleOperationStart 
        $ScaleOperationEnd = $line.ScaleOperationEnd 
        $NormalVMSize = $line.NormalVMSize 
        $CurrentVMSize = $line.CurrentVMSize  
        $ScaleDownSize = $line.ScaleDownSize  
        $VMScaleWindow = $line.VMScaleWindow
        $ScaleOperation = $line.ScaleOperation 
        $AzVMStatusCode = $line.AzVMStatusCode  
        $IsDaylightSavingTime = $line.IsDaylightSavingTime  
        $ScaleOperationResult = $line.ScaleOperationResult  
         if($AzVMStatusCode -eq "OK")
        {
            $BGColor10 = "$greenColor"
        }
        else 
        {
            $BGColor10 = "$redColor"    
        }
        #The below is only to set the color code.
        Switch($ScaleOperation)
        {
            "None"
            {
                $BGColor8 = "$REDCOLOR"
                $BGColor9 = "$REDCOLOR"
            }
            "ScaleDown"
            {
                   if($ScaleOperationResult -eq "OK")
                    {
                            $BGColor12 ="$greencolor"
                    }  
                  else
                    {
                            $BGColor12 ="$redcolor"
                    }
            }
            "ScaleUP"
            {
                    if($ScaleOperationResult -eq "OK")
                    {
                            $BGColor12 ="$greencolor"
                    }  
                  else
                    {
                            $BGColor12 ="$redcolor"
                    }
            }
            "BUOverRide"
            {
                $ScaleOperationResult = "NA - BU has set scale option as FALSE - No action taken at this time."
                $BGColor6 = "$ORANGECOLOR"
                $BGColor7 = "$ORANGECOLOR"
                $BGColor8 = "$ORANGECOLOR"
                $BGColor9 = "$ORANGECOLOR"
                $ScaleDownSize = "N/A"
            }
        }
     $dataRow = "
        <tr>

        <td width='10%' bgcolor=`'$BGColor1`'  align='center'>$VMName</td>
        <td width='10%' bgcolor=`'$BGColor2`'  align='center'>$resourceGroup</td>
        <td width='10%' bgcolor=`'$BGColor2`'  align='center'>$CurrentBatch</td>
        <td width='10%' bgcolor=`'$BGColor3`'  align='center'>$ScaleOperationStart</td>
        <td width='10%' bgcolor=`'$BGColor4`'  align='center'>$ScaleOperationEnd</td>
        <td width='10%' bgcolor=`'$BGColor5`'  align='center'>$NormalVMSize</td>
        <td width='10%' bgcolor=`'$BGColor6`'  align='center'>$CurrentVMSize</td>
        <td width='10%' bgcolor=`'$BGColor7`'  align='center'>$ScaleDownSize</td>
        <td width='10%' bgcolor=`'$BGColor8`'  align='center'>$VMScaleWindow</td>        
        <td width='10%' bgcolor=`'$BGColor9`'  align='center'>$ScaleOperation</td>        
        <td width='10%' bgcolor=`'$BGColor10`'  align='center'>$AzVMStatusCode</td>
        <td width='10%' bgcolor=`'$BGColor11`'  align='center'>$IsDaylightSavingTime</td>
        <td width='10%' bgcolor=`'$BGColor12`'  align='center'>$ScaleOperationResult</td>
        
        
        </tr>
        "
        Add-Content $HtmlReportFileName $dataRow;
        $BGColor1 = $BGColor2 = $BGColor3 = $BGColor4 = $BGColor5 = $BGColor6 = $BGColor7 = $BGColor8 = $BGColor9 = $BGColor10 = $BGColor11 = $BGColor12 = ""
     }
    SendEmail $EmailParameters
    CleanupBlobs_KillAllDeployments $ConsolidatedReport
}
Else
{
    #if its not master pod, then upload the report to blob.
    UploadReporttoBlob $CurrentBatch
}
#Start-sleep -s 90000 #for troubleshooting only.
#Trigger the build and check the status after it finishes.
#Only the master pod -- the pod that has the variable value of $env:batch1 set


$error | Out-File /scripts/logs.txt -append
$CurrentBatch = (get-childitem env: | where {$_.Name -like "*batch*"}| Select Name).Name
$newfile = "$CurrentBatch"+".txt"
 
Copy-Item /scripts/logs.txt /scripts/$newfile
Set-AzStorageBlobContent -Blob $newfile -Container $containerName -File "/scripts/$newfile" -Force
#azDevops should kill this job and the below code to run forever should even be entering. If it did something went wrong or the pipeline is running for too long.
do
{
    $i = "0"
    Start-Sleep -s 600
}While($i -eq "0")
#for Troubleshooting only -- comment $buildresponse = TriggerBuild and uncomment start-sleep