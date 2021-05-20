# Repository structure

|argocd-clusters-managed | Primary folder - containing applications and configs for each managed cluster, which MAY make use of common resources, such as argocd-helm-charts and argocd-k8s-config. Each clusterfolder is actually a Helm chart - hence applications are put as yaml in ```templates``` folder. |
| --- | --- |
|argocd-helm-charts | Contains ArgoCD helm charts, that points to the actual helm charts (as a dependency listed in Charts.yaml) - and with the default values we want. Each cluster can add override/extra values by listing an extra valuesfile in their argocd-clusters-managed/$clustername folder. |
|argocd-k8sconfig | Kubernetes config objects. Used by all in ```common``` and per-cluster in their indidivual $clustername folder. |
|argocd-application-templates | collection of applications, to be optionally modified and copied into ```argocd-clusters-managed/$clustername/templates``` to be installed on that cluster. |

# Add a new cluster to be managed by this repository/argocd

## Create namespace for argocd installation
```
kubectl create namespace argocd
kubectl config set-context --current --namespace=argocd
```

## Create secret for git repo access

### for https access to git repos

Add secret with a username and a password (a personal-access-token) that is valid and has access to that repo.

* To get the personal-access-token
  1. Go to Profile->Access Tokens
  2. Give any name (argo-cd-microk8s) and select "read_repository, write_repository"
* Create secret via https
  ```
  kubectl create secret generic argo-cd-blackwoodseven-github --from-literal=username=KlavsKlavsen --from-literal=password='234dfaf23rf2323232323232323xxxxxxxxxxxxx'
  ```

### for SSH access to git repos

Setup gitlab user and generate SSH keyset (and add public part to that gitlab user).
Grant that user ONLY developer access to the projects it needs. Make sure those have master branch and tags protected in config.

add secret with ssh keys for gitlab argocd SSH access:
```
kubectl create secret generic argocd-sshkey --from-file=ssh-privatekey=/path/to/.ssh/id_rsa --from-file=ssh-publickey=/path/to/.ssh/id_rsa.pub
```

and make sure `sshPrivateKeySecret.name` for repositories in
`argocd-clusters-managed/$yourclustername/values-argocd.yaml` has this repo added, matching above secretname.


## Install argo-cd
```
helm dep update argocd-helm-charts/argo-cd
helm install -n argocd argo-cd argocd-helm-charts/argo-cd
```
## Get the pods status

```
kubectl  get pods
NAME                                                    READY   STATUS              RESTARTS   AGE
argo-cd-argocd-server-76687b5447-7h5pb                  0/1     ContainerCreating   0          2m20s
argo-cd-argocd-repo-server-6bd696f59b-wwr9r             0/1     ContainerCreating   0          2m20s
argo-cd-argocd-application-controller-d6c576f5d-5q28r   0/1     ContainerCreating   0          2m20s
argo-cd-argocd-redis-7dfd84cf48-wtfvq                   1/1     Running             0          2m20s
```

Login to the UI. To get the credentials refer
[argocd admin credentials](https://argoproj.github.io/argo-cd/getting_started/#4-login-using-the-cli).

## Install root argocd application - that manages the rest
Install argo-cd root app using:
```
helm template argo-cd-helm-apps/your-cluster-name --show-only templates/root.yaml | kubectl apply -f -
```

And its Chart.yaml points to this repo argo-cd-helm-apps - so once Root app is installed - it'll pick up the apps in there and start setting them up.

Now we can remove helm management of argo-cd - as argo-cd manages itself (as argo-cd is one of the apps in above apps folder).

```
kubectl delete secret -l owner=helm,name=argo-cd
```

# Secrets handling

IF a helm chart creates a secret - ArgoCD will expect it to remain unchanged (otherwise complain application is out-of-sync). 
IF this happens - it means you have a secret thats changed via the application (typicly user login password) - and we NEED backup of these.
To resolve out-of-sync complaint in ArgoCD - AND backup/recovery do this:
1. let helm chart create secret and application generate it - so you get out-of-sync complaint from ArgoCD.
2. dump secret in json format, remove unnecessary metadata/helm labels and encode into cluster secrets repo and delete the secret from k8s (before pushing to secrets repo).
3. update values for chart as to NOT generate secret. Typicly setting is called something like useExistingSecret: $name-of-secret
## Debugging
* you might see pods getting evicted, mostly likely disk is used around 70% or you have less disk size (> 5GB).
  to fix it increase the disk size
  ```
  root@htzsb44fsn1a ~ # kubectl get pods
  NAME                                                    READY   STATUS    RESTARTS   AGE
  argo-cd-argocd-application-controller-d6c576f5d-4d9bv   0/1     Evicted   0          84m
  argo-cd-argocd-application-controller-d6c576f5d-5xwq5   0/1     Evicted   0          44m
  argo-cd-argocd-application-controller-d6c576f5d-7cm78   0/1     Evicted   0          100m
  ```
* Please refer: [Wiki for kubernetes](https://gitlab.enableit.dk/obmondo/wiki/-/tree/master/internal/kubernetes)

# Testing applications - before doing a PR / MR

## Test helm values genereate the yaml you want
1. run ```helm dep up argocd-helm-charts/<nameofchart>```
2. run ```helm template argocd-helm-charts/<nameofchart> --values argocd-clusters-managed/<targetcluster>/values-<nameofchart>.yaml >/tmp/before.yaml```
3. READ yaml and see if you like it.. adjust values to your liking and run 2. again - saving to ```/tmp/after.yaml```
4. run: ```diff -bduNr /tmp/before.yaml /tmp/after.yaml``` - verify the changes your value update should have caused - did actually happen

## Install the application manually to verify
1. create/copy application YAML - and set: targetRevision to <yourbranchname> instead of HEAD
2. Load that yaml manually (k create -ns argocd -f yourapplication.yaml)
3. Work in your branch - adjust values as needed etc.
4. When it works.. Simply update the application yaml to pointing to targetRevision: HEAD and make your MR/PR

# Helm build dependency

Run the helm-dep-up.sh script to build the dependecy. The script runs the helm dep up command based on what is the value of upstream. IF upstream is true - it downloads the charts from upstream repo url and if false It download charts from our ghcr repo. Path variable is the helm chart path

```bash
./helm-dep-up.sh -u true -p argocd-helm-charts/yetibot
```

# Helm cache repo

```bash
./helm-chart-cache.sh -r ghcr.io/Obmondo -p ******
````
Above will push the charts to ghcr.io/Obmondo registry
Now, we just need to add the charts lock files and raise the MR
