#!/usr/bin/env bash
set -x
run_test="true"


help_user(){
      printf "\nThis script upgrades helm chart according to given values\n"
      echo "Must values: "
      echo "--cluster-name                  The  eks cluster name "
      echo "--role-arn            The eks node instance role arn"
      echo "Options"
      echo "--lb-fqdns          The public network load balancer fqdns"
      echo " "
}

msg(){
    printf "\nINFO: $1\n"
}

err_msg(){
    printf "\nERROR: $1\n"
}

warn_msg(){
    printf "\n>>>>>WARNING: $1\n"
}

while (( "$#" )); do
  case "$1" in
    -h|--help)
      help_user
      shift
      ;;
    --cluster-name)
      CLUSTER_NAME=$2
      shift
      shift
      ;;
    --role-arn)
      ROLE_ARN=$2
      shift
      shift
      ;;
    --lb-fqdns)
      EKS_LB=$2
      shift
      shift
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      echo ""
      help_user
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done






function eks_login(){
    echo "loging to eks cluster named ${CLUSTER_NAME} to deploy configure ndoe script "
    sudo aws eks --region us-west-2 update-kubeconfig --name ${CLUSTER_NAME} --no-verify-ssl
}


eks_login



cat <<EOF > deployment
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${ROLE_ARN}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system
EOF

msg "deploying config maps "
sudo kubectl apply -f deployment

nodes_status=`sudo kubectl get nodes | awk '{print $2}' | grep -v STATUS | wc -l`
x=1
while [ ${nodes_status} -le  2 ] || [ $x -ge 500 ] ; do
        x=$(( $x + 1 ))
	    msg "waiting for nodes to be up :) ${nodes_status} "
        nodes_status=`sudo kubectl get nodes | awk '{print $2}' | grep -v STATUS | wc -l`
        for dns in `kubectl get pods -n kube-system | grep dns | grep -v Running | awk '{print $1}'` ; do kubectl delete pods --grace-period=0 --force -n kube-system $dns ; done
        sleep 30

done
msg "Nodes looks just ! fine !!"


kube_status=`sudo kubectl get pods -n kube-system | grep -v Running | grep -v NAME | wc -l`
x=1
while [ ${kube_status} !=  "0" ] || [ $x -ge 500 ] ; do
        x=$(( $x + 1 ))
	    msg "waiting for helm to be up :) ${kube_status} "
        hkube_status=`sudo kubectl get pods -n kube-system | grep -v Running | grep -v NAME | wc -l`
        sleep 10
done
msg "kube is up :)  "



msg "install helm "
sudo helm init --service-account tiller --history-max 2
helm_status=`sudo kubectl get pods -n kube-system | grep tiller | awk '{print $3}'`
x=1
while [ ${helm_status} !=  "Running" ] || [ $x -ge 500 ] ; do
        x=$(( $x + 1 ))
	    msg "waiting for helm to be up :) ${helm_status} "
        helm_status=`sudo kubectl get pods -n kube-system | grep tiller | awk '{print $3}'`
        sleep 10
done
msg "Helm is running so fun :) "

