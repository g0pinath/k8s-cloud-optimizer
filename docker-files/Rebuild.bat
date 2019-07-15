cd "c:\temp\docker-files\pod-A"
kubectl delete cronjobs --all -n devops-team
kubectl delete deployments --all -n devops-team


docker build . -t devops-team-image-pod-a:v10
az acr login --name <acrname>
docker tag devops-team-image-pod-a:v10 <acrname>.azurecr.io/devops-team-image-pod-a:v10
docker push <acrname>.azurecr.io/devops-team-image-pod-a:v10
cd "c:\temp\docker-files\cronjob-pod-A"
docker build . -t devops-team-image-cronjob:v10
docker tag devops-team-image-cronjob:v10 <acrname>.azurecr.io/devops-team-image-cronjob:v10
docker push <acrname>.azurecr.io/devops-team-image-cronjob:v10
cd..
cd..
cd k8s-yaml
kubectl apply -f cronjob.yaml
kubectl apply -f pod-deployment-template.yaml
kubectl get pods -n devops-team


#commit to git

cd "C:\temp"
git add --all 
git commit -m "Rebuild"
git push origin master
kubectl delete deployments --all -n devops-team
#let the cronjob start the deployment like it should.

