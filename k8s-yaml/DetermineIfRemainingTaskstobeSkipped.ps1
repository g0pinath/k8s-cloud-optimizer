param($BuildSourcesDirectory)

$Deployments = kubectl get deployments -n devops-team
Write-Output "got deployments"
if(($Deployments|Measure-Object).Count -gt "1")
{
    Write-Output "If I am here - POD called me - its done - so get rid of it"
    
    $csv = Import-CSV "$BuildSourcesDirectory\nestedtemplates\AKS\docker-files\pod-A\InputCSV.csv"
    [int]$j=1 
    [int]$NumberofBatches = ($csv | Select-Object Batch -Unique|Measure-Object).Count
    For($k=1; $k -le $NumberofBatches; $k++)
    {
         $secretname = "batch"+$j   
         $deploymentName = "devops-optimizer-site-deployment-"+"batch"+$j   
         Write-Output "Deleting secret - $secretname == deployment  $deploymentName "
         kubectl delete secrets $secretname -n devops-team
         kubectl delete deployments $deploymentName -n devops-team
         $j+=1
    }

     kubectl delete secrets da-creds-lab -n devops-team
     $SkipRemainingTasks = "TRUE"
     Write-Host ("##vso[task.setvariable variable=SkipRemainingTasks]$SkipRemainingTasks") 
}
else
{
     $SkipRemainingTasks = "FALSE"
     Write-Output "I am in else"
     #The below is not really required, as they wont(shouldnt) exist anyway.
     kubectl delete secrets da-creds-lab -n devops-team
     ForEach($row in $csv)
    {
         $secretname = "batch"+$j   
         $deploymentName = "devops-optimizer-site-deployment-"+"batch"+$j   
         Write-Output "Deleting secret - $secretname == deployment  $deploymentName "
         kubectl delete secrets $secretname -n devops-team
         kubectl delete deployments $deploymentName -n devops-team
    }
     Write-Host ("##vso[task.setvariable variable=SkipRemainingTasks]$SkipRemainingTasks") 
}