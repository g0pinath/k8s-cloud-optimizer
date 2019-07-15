
param(
    $SkipRemainingTasks,
    $BuildSourcesDirectory)
    
    Write-Output "SkipRemainingTasks -- $SkipRemainingTasks"
    #If the pod called the pipeline, then the below IF condition is skipped. If the CronJob called this pipeline, then the below IF condition is TRUE.
    if($SkipRemainingTasks -eq "FALSE")
    {

    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
    Install-Module -Name powershell-yaml -Force -Verbose -Scope CurrentUser
    Set-Location $BuildSourcesDirectory
    [string[]]$fileContent = Get-Content "$BuildSourcesDirectory\nestedtemplates\AKS\k8s-yaml\pod-deployment-template.yaml"
    $csv = Import-CSV "$BuildSourcesDirectory\nestedtemplates\AKS\docker-files\pod-A\InputCSV.csv"
    $yamlcontent = ''
    #join as new line separated file.
    foreach ($line in $fileContent) 
    { 
        $yamlcontent = $yamlcontent + "`n" + $line 
    }
    #Get the batch count.    
    [int]$NumberofBatches = ($csv | Select-Object Batch -Unique|Measure-Object).Count
    [int]$NumberofBatchesplusone = $NumberofBatches + 1
    [string]$finalyamlcontent = ""
    #Create a string that copies the template N number of times, N = numberofbatches in CSV.
    For($i=1;$i -lt $NumberofBatchesplusone; $i++)
    {
        $finalyamlcontent = $finalyamlcontent + $yamlcontent
    }
    #Convert the string to array and get rid of the last array value.
    $finalyamlcontentArr = $finalyamlcontent -split "---"
    $count = ($finalyamlcontentArr|measure-object).Count-2 # to skip the last line that is empty.
    $finalyamlcontentArr = $finalyamlcontentArr[0..$count]
    #For index.
    [int]$j=1 
    
    foreach($item in $finalyamlcontentArr)
    {
            
            $yamlitem = @{}
            $yamlitem = $item | Convertfrom-Yaml
            #to process each data field under the secret.
            [string]$currentBatch = "batch"+$j
            #create the secret for each batch, this will be mapped into the pod as ENV VAR.
            kubectl create secret generic $currentBatch --from-literal=$currentBatch=$currentBatch -n devops-team
            $yamlitem.metadata.name = "devops-optimizer-site-deployment-"+"batch"+"$j"
            $yamlitem.spec.selector.matchLabels.app = "devops-optimizer-site-pod-" + "batch" + "$j"
            $yamlitem.spec.template.metadata.labels.app = "devops-optimizer-site-pod-" + "batch" + "$j"
            $yamlitem.spec.template.spec.containers[0].name = "devops-optimizer-site-pod-" + "batch" + "$j"
            $yamlitem.spec.template.spec.containers[0].env[0].name = "batch" + "$j"
            $yamlitem.spec.template.spec.containers[0].env[0].valueFrom.SecretKeyRef.name = "batch" + "$j"
            $yamlitem.spec.template.spec.containers[0].env[0].valueFrom.SecretKeyRef.key = "batch" + "$j"
            $yamlitem = $yamlitem | ConvertTo-Yaml
            [string]$fname = "Temp-"+$j+".yaml" # for each secret split by --- a file will be created and then finally they will be merged back.
            $yamlitem | out-file $fname
            $j+=1 # move to next batch.
    }
    $allFiles = (Get-ChildItem -Filter temp* | Select-Object Name).Name
    #parse each temp yaml file and use convertfrom-yaml to combine them to a single file.
    Foreach($item in $allfiles)
    {
        $content = get-content $item | convertto-yaml
        $yaml += (ConvertFrom-YAML $content) +  "---"
        #Fit them back together...
    }
    Set-Location nestedtemplates\AKS\k8s-yaml
    $yaml |  Out-File pods-deployment-actual.yaml
    #apply the k8s templates.
    Get-ChildItem -Filter temp*  | Remove-Item
    Write-Output "----"
    kubectl apply -f "pods-deployment-actual.yaml"
    Write-Output "----"
    #kubectl create secret tls aks-ingress-tls --namespace ingress-basic --key azk8_site.key --cert azk8_site.crt
    
    }