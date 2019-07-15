param(
$vstspat,
$servicePrincipalClientId,
$servicePrincipalClientSecret,
$emailusername,
$emailpassword,
$BuildSourcesDirectory)

Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
Install-Module -Name powershell-yaml -Force -Verbose -Scope CurrentUser
cd $BuildSourcesDirectory


[string[]]$fileContent = Get-Content "$BuildSourcesDirectory\nestedtemplates\AKS\k8s-yaml\aks-secrets.yml"
$content = ''
#join as new line separated file.
foreach ($line in $fileContent) { $content = $content + "`n" + $line }
#convertfrom-yaml natively cant handle multiple items separated via ---
$aftersplit = $content -split "---"
$aftersplit |measure
#Dump each item in this split array into a yaml file.
[int]$i=0

$secretsList = @(
@("vstspat"),
@("emailusername", "emailpassword")
)
#The above list has to exactly match whats in secrets data.

foreach($item1 in $aftersplit)
{
 [string]$j = $i #j is for file number.
 
 #to skip the last item. The split has N+1 secrets separated by ---, so we are skipping the last.
     if(($aftersplit |Measure).COunt -ge $i+1)
     {
     $currSecretArray =@()
     $currSecretArray = $secretsList[$i]
     $yamlitem = @{}
     $yamlitem = $item1 | Convertfrom-Yaml
      Write-Output "Before FOR"
     #to process each data field under the secret.
     Foreach($secret in $currSecretArray)
     {
        #k8s wont take non base 64 encoded if the secret type is opaque.
        
        [string]$secretValue=""
        $secretValue = Get-Variable $secret -ValueOnly # the value of secret will be changing for each iteration of [array]$secretsList

        $encodedSecret = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($secretValue)) # will resolve to $(websecrettest1) for first iteration.
        #$DecodedText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EncodedText)) - to decode
        #K8s cant handle UNICODE -- has to be UTF8
        $yamlitem.data.$secret = $encodedSecret 
         $encodedSecret 

        write-output "*************"
     }
     
     $yamlitem = $yamlitem | ConvertTo-Yaml
     [string]$fname = "Temp-"+$j+".yaml" # for each secret split by --- a file will be created and then finally they will be merged back.
     $yamlitem | out-file $fname
     $i+=1 # move to next secret.
     }
  }

$allFiles = (Get-ChildItem -Filter temp* | Select Name).Name
#parse each yaml file and use convertfrom-yaml to manipulate its values.
Foreach($item in $allfiles)
{
$content = get-content $item | convertto-yaml
$yaml += (ConvertFrom-YAML $content) +  "---"
#Fit them back together...
}

cd nestedtemplates\AKS\k8s-yaml
$yaml |  Out-File aks-secrets-actual.yaml

Get-ChildItem -Filter temp*  | Remove-Item
kubectl apply -f "namespaces.yml"
kubectl apply -f "rbac.yml"
kubectl apply -f "aks-secrets-actual.yaml"

kubectl delete secrets da-creds-icldev -n devops-team

#kubectl create secret tls aks-ingress-tls --namespace ingress-basic --key azk8_site.key --cert azk8_site.crt
Remove-item aks-secrets-actual.yaml -force


####SSL secrets

#download secrets from KV and convert base 64 to file.
