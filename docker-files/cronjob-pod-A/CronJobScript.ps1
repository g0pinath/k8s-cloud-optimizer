Import-Module PowerShellGet
Install-Module -Name Az.Compute -Force -Verbose
Import-Module Az.Compute
$error | out-file /scripts/logs.txt -append

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
[string]$IsDaylightSavingTime = (Get-Date).IsDaylightSavingTime() # wonder why but from the pod it returns false in summer, although from Windows 10 its TRUE in summer.
#Set colors for table cell backgrounds
#$redColor = "#FF0000"
#$greenColor = "#01DF3A"
#$orangeColor = "#FBB917"
#$whiteColor = "#FFFFFF"
Set-Location scripts
[string]$HtmlReportFileName= "azDevops_ScaleDownReport_$(get-date -format MM-dd-yyyy).html"
[string]$LogsPath="azDevops_ScaleDownLogs_$(get-date -format MM-dd-yyyy).txt"
[string]$htmlblobName="scripts/reports/"+$HtmlReportFileName
[string]$logsblobName="scripts/Logs/"+$LogsPath
[string]$HeadingofReport="Azure Report - AZ Resource CronJob Report"

#We are using the method of sending the parameters are arguments, using hashtable in used later in the script.
$HTMLTitleoutput = HTMLHeader4Reports  $HeadingofReport
$ColumnNameOutput = TableHeader4Reports CronJobStartTime_EST CronJobEndTime_EST CronJobName ScaleOperation CronJobBuildStatus CronJobBuildResult 
#The log file and the html file has to exist before I can add content to it.
New-Item -ItemType File -Name $HtmlReportFileName # creates in c:\temp
New-Item -ItemType File -Name $LogsPath
Add-Content $HtmlReportFileName $HTMLTitleoutput # this is thoe first row of the report containing the Title
Add-Content $HtmlReportFileName $ColumnNameOutput # this is the second row of the report containing the headers

Function SendEmail($EmailParameters)
{    
    $body = Get-Content $HtmlReportFileName -Raw
    Send-MailMessage -To $EmailParameters.ToAddress `
        -Subject $EmailParameters.MessageSubject  `
        -UseSsl -Port 587 -Body $body -SmtpServer 'smtp.office365.com' `
        -From $EmailParameters.FromAddress  -BodyAsHtml -Credential $O365creds
 }
$vstspat = get-content /etc/vsts-pat/vstspat

$EmailUserName = Get-Content "/etc/emailcredentials/emailusername"
$EmailPassword = Get-Content "/etc/emailcredentials/emailpassword"
$user="gopinath.thiruvengadam@trgc.com"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$vstspat)))

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
        }While($Status -ne 'completed' -and $timelefttowait -ne '0')
        Return $buildresponse 
}
#Trigger the build and check the status after it finishes.

if($IsDaylightSavingTime -eq "False")
{
    $CronJobStartTime = ((Get-Date).ToUniversalTime()).addhours(-4) # in EST adjusting for daylight savings time.
}
Else
{
    $CronJobStartTime = ((Get-Date).ToUniversalTime()).addhours(-5) # in EST adjusting for daylight savings time.
}
$buildresponse = TriggerBuild

if($IsDaylightSavingTime -eq "False")
{
    $CronJobEndTime = ((Get-Date).ToUniversalTime()).addhours(-4) # in EST adjusting for daylight savings time.
}
Else
{
    $CronJobEndTime = ((Get-Date).ToUniversalTime()).addhours(-5) # in EST adjusting for daylight savings time.
}
[string]$URL = $buildresponse.URL
$FinalBuildStatus = (Invoke-RestMethod -Method Get -UseDefaultCredentials -ContentType application/json -Uri $URL -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}).Status
$FinalBuildResult =  (Invoke-RestMethod -Method Get -UseDefaultCredentials -ContentType application/json -Uri $URL -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}).result
Write-Output "Final BuildResult-->" $FinalBuildResult

$CronJobName = "cronJob-Invoke-PodA"
$ScaleOperation = "ScalingDown"
$dataRow = "
<tr>

<td width='10%' bgcolor=`'$BGColor1`'  align='center'>$CronJobStartTime</td>
<td width='10%' bgcolor=`'$BGColor1`'  align='center'>$CronJobEndTime</td>
<td width='10%' bgcolor=`'$BGColor1`'  align='center'>$CronJobName</td>
<td width='10%' bgcolor=`'$BGColor1`'  align='center'>$ScaleOperation</td>
<td width='10%' bgcolor=`'$BGColor1`'  align='center'>$FinalBuildStatus</td>
<td width='10%' bgcolor=`'$BGColor1`'  align='center'>$FinalBuildResult</td>
</tr>
"
Add-Content $HtmlReportFileName $dataRow; # third row(and fourth row for each value in the array) of the report adding values


$SecurePassword=convertto-securestring -AsPlainText -Force -String $EmailPassword
$O365creds = New-object -TypeName System.Management.Automation.PSCredential -ArgumentList ($EmailUserName,$SecurePassword) 
#Be careful with the hyphen if you are reusing the above!!!  -- https://stackoverflow.com/questions/45863545/new-object-pscredential-not-working-using-unicode-punctuation-syntactically Welcome to Linux(or blame it Linux)

[hashtable]$EmailParameters = @{"FromAddress"="TRGO365SupportToolDev@trgc.com"; `
"ToAddress"="TRGAzureReports@trgc.com";"MessageSubject"="Azure Report - AZ Resource CronJob Report"; `
"HtmlBlobName"="$htmlblobName";"Container"=$Container;"LogsBlobName"=$LogsblobName}
SendEmail $EmailParameters
