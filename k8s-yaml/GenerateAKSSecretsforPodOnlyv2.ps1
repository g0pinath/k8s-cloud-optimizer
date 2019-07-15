param(
$vstspat,
$servicePrincipalClientId,
$servicePrincipalClientSecret,
$emailusername,
$SkipRemainingTasks,
$emailpassword,
$BuildSourcesDirectory)

Write-Output "SkipRemainingTasks -- $SkipRemainingTasks"
#If the pod called the pipeline, then the below IF condition is skipped. If the CronJob called this pipeline, then the below IF condition is TRUE.
if($SkipRemainingTasks -eq "FALSE")
{
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
    Install-Module -Name powershell-yaml -Force -Verbose -Scope CurrentUser
    Set-Location $BuildSourcesDirectory
    [string[]]$fileContent = Get-Content "$BuildSourcesDirectory\nestedtemplates\AKS\k8s-yaml\aks-secrets.yaml"
    $content = ''
    #join as new line separated file.
    foreach ($line in $fileContent) { $content = $content + "`n" + $line }
    #convertfrom-yaml natively cant handle multiple items separated via ---
    $aftersplit = $content -split "---"
    $aftersplit | measure-object
    $count = ($aftersplit|measure-object).Count-2 # to skip the last line that is empty.
    $aftersplit = $aftersplit[0..$count]
    #pointer for temp file and secrets inner array.
    [int]$i=0
    #SecretList is a 2-dimensional array aka array of arrays.
    $secretsList = @(
    @("vstspat"),
    @("emailusername", "emailpassword"),
    @("servicePrincipalClientId", "servicePrincipalClientSecret")
    )
    #The above list has to exactly match whats in secrets data section on data in aks-secret.yaml file. 
    #For example emailcredentials secret has the below in the template, so the array values should match this exactly.
    #emailusername: frompipeline
    #emailpassword: frompipeline
    #The below loop will create an individual secret file prefixed with temp and will inject the actual secrets based on the template aks-secret.yaml file.
    foreach($item1 in $aftersplit)
    {
    [string]$j = $i #j is for file number.
        
        $currSecretArray =@()
        #Each secret can be an array of secret
        $currSecretArray = $secretsList[$i]
        Write-Output "Processing currSecretArray -- $currSecretArray"
        $yamlitem = @{}
        $yamlitem = $item1 | Convertfrom-Yaml
        #to process each data field under the secret.
        Foreach($secret in $currSecretArray)
        {
            #k8s wont take non base 64 encoded if the secret type is opaque.
            Write-Output "Inside inner for"
            [string]$secretValue=""
            Write-Output "-- secret --$secret"
            $secretValue = Get-Variable $secret -ValueOnly # the value of secret will be changing for each iteration of [array]$secretsList
            write-output "*******-----$secretValue-----******"
            $encodedSecret = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($secretValue)) # will resolve to $(websecrettest1) for first iteration.
            #$DecodedText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EncodedText)) - to decode
            #K8s cant handle UNICODE -- has to be UTF8

            write-output "*******-----$encodedSecret-----******"
            write-output "*************"
            write-output "*************"
            $yamlitem.data.$secret = $encodedSecret 
            $encodedSecret 

            write-output "*************"
        }
        
        $yamlitem = $yamlitem | ConvertTo-Yaml
        [string]$fname = "Temp-"+$i+".yaml" # for each secret split by --- a file will be created and then finally they will be merged back.
        $yamlitem | out-file $fname
        $i+=1 # move to next secret.
        
    }
    $allFiles = (Get-ChildItem -Filter temp* | Select Name).Name
    #parse each temp yaml file and use convertfrom-yaml to combine them to a single file.
    Foreach($item in $allfiles)
    {
        $content = get-content $item | convertto-yaml
        $yaml += (ConvertFrom-YAML $content) +  "---"
        #Fit them back together...
    }
    Set-Location nestedtemplates\AKS\k8s-yaml
    $yaml |  Out-File aks-secrets-actual.yaml
    #apply the k8s templates.
    Get-ChildItem -Filter temp*  | Remove-Item
    Write-Output "----"
    kubectl apply -f "namespaces.yaml"
    Write-Output "----"
    kubectl apply -f "rbac.yaml"
    Write-Output "----"
    gc "aks-secrets-actual.yaml"
    kubectl apply -f "aks-secrets-actual.yaml"
    Write-Output "----"
    kubectl apply -f "cronjob.yaml"
    Write-Output "----"
    
    #kubectl create secret tls aks-ingress-tls --namespace ingress-basic --key azk8_site.key --cert azk8_site.crt
    Remove-item aks-secrets-actual.yaml -force
}