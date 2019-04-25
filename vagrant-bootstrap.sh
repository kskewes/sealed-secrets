#!/bin/bash
# Bitnami-Labs Sealed Secrets - Vagrant Bootstrap Script

# How to use:
# 1. Edit environment variables in setup_env(), potentially
# 2. `vagrant up`
# 3. `vagrant ssh` followed by `sudo -i` to escalate to root.
# 4. `vagrant destroy`
#
# Notes:
# 1. This script aims to be as close to the .travis-ci.yml process as possible
#      including variable names and running as root. Deviations are:
#      - CONTROLLER_IMAGE: Use 'latest' tag rather than TRAVIS env vars.
#      - make clean before building
# 2. Minikube, kubectl, kubecfg versions defined inline
# 3. TODO?: Make script idempotent so can iterate and re-test.
# 4. TODO?: Tidy up variables, remove TRAVIS_'es

# Integration test error on GO 1.11 and 1.12:
#     vagrant: ginkgo -p -tags 'integration' integration -- -kubeconfig /root/.kube/config -kubeseal-bin /root/go/src/github.com/bitnami-labs/sealed-secrets/kubeseal -controller-bin /root/go/src/github.com/bitnami-labs/sealed-secrets/controller
#    vagrant: Failed to compile integration:
#    vagrant:
#    vagrant: # github.com/bitnami-labs/sealed-secrets/integration
#    vagrant: integration/kubeseal_test.go:230:6: c declared but not used
#    vagrant: vet: typecheck failures
#    vagrant:
#    vagrant: Ginkgo ran 1 suite in 54.131671689s
#    vagrant: Test Suite Failed
#    vagrant: Makefile:68: recipe for target 'integrationtest' failed

function setup_env() {

	print_header 'Started Setting Environment Variables...'

	if ! grep -q 'Sealed Secrets' /root/.profile; then
		cat >> /root/.profile <<- EOF
		# Sealed Secrets
		export GOPATH="${HOME}/go"
		export PATH="${PATH}:/usr/local/go/bin:/root/go/bin"
		# Working GO Versions:
		# 1.9.7
		# 1.10.8
		# Not working GO Version - fails integration test:
		# 1.11.9 - 2019/04/21
		# 1.12.4 - 2019/04/21
		export TRAVIS_GO_VERSION=1.10.8
		export TRAVIS_OS_NAME=linux
		export TRAVIS_TAG=vagrant
		export TRAVIS_BUILD_ID=git
		# Working K8S Versions:
		# 1.12.7 - note docker-ce version 18.06 required
		# 1.13.5
		# 1.14.1
		export INT_KVERS=v1.14.1
		export INT_SSC_CONF=controller.yaml

		export CONTROLLER_IMAGE_NAME=quay.io/bitnami/sealed-secrets-controller
		export CONTROLLER_IMAGE=quay.io/bitnami/sealed-secrets-controller
		export MINIKUBE_WANTUPDATENOTIFICATION=false
		export MINIKUBE_WANTREPORTERRORPROMPT=false
		export MINIKUBE_HOME="${HOME}"
		export CHANGE_MINIKUBE_NONE_USER=true
		export KUBECONFIG="${HOME}/.kube/config"
		EOF
	fi
	# ENV vars are required for provisioning so source them now.
	# shellcheck disable=SC1091
	source /root/.profile
	env

	print_header 'Finished Setting Environment Variables...'
}

function install_go() {
	print_header 'Started installing GO...'

	echo "Installing Golang $TRAVIS_GO_VERSION..."
	VERSION="$TRAVIS_GO_VERSION"
	OS="$TRAVIS_OS_NAME"
	ARCH="amd64"
	apt install -y wget
	if [ ! -f "go${VERSION}.${OS}-${ARCH}.tar.gz" ]; then
		wget -q "https://dl.google.com/go/go${VERSION}.${OS}-${ARCH}.tar.gz"
		tar -C /usr/local -xzf "go${VERSION}.${OS}-${ARCH}.tar.gz"
	fi

	mkdir -p "${GOPATH}/src"
	mkdir -p "${GOPATH}/bin"
	mkdir -p "${HOME}/.go"

	print_header 'Finished installing GO...'
}


function install_kubernetes() {
	print_header 'Started installing Kubernetes - minikube and kubectl...'

	echo "Installing Docker..."
	apt install -y \
		apt-transport-https \
		ca-certificates \
		curl \
		gnupg-agent \
		software-properties-common
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	add-apt-repository \
		"deb [arch=amd64] https://download.docker.com/linux/ubuntu \
		$(lsb_release -cs) \
		stable"
	apt update

	if [[ "$INT_KVERS" =~ ^v1\.12\. ]]; then
		apt install -y docker-ce=18.06.3~ce~3-0~ubuntu
	else
		apt install -y \
			docker-ce \
			docker-ce-cli \
			containerd.io
	fi

	echo "Installing minikube..."
	if [ "$INT_KVERS" != "" ]; then
	  v=1.0.0
	  if ! which minikube-$v; then
		wget -q -O "$GOPATH/bin/minikube-$v" \
		   "https://storage.googleapis.com/minikube/releases/v$v/minikube-$(go env GOOS)-$(go env GOARCH)"
		chmod +x "$GOPATH/bin/minikube-$v"
	  fi
	  ln -sf "minikube-$v" "$GOPATH/bin/minikube"

	  echo "Installing kubectl..."
	  v=$INT_KVERS
	  if ! which "kubectl-$v"; then
		wget -q -O "$GOPATH/bin/kubectl-$v" "https://storage.googleapis.com/kubernetes-release/release/$v/bin/$(go env GOOS)/$(go env GOARCH)/kubectl"
		chmod +x "$GOPATH/bin/kubectl-$v"
	  fi
	  ln -sf "kubectl-$v" "$GOPATH/bin/kubectl"

	  mkdir -p "$(dirname "$KUBECONFIG")" "$HOME/.minikube"
	  touch "$KUBECONFIG"
	  "$GOPATH/bin/minikube" start --vm-driver=none \
		--extra-config=apiserver.authorization-mode=RBAC \
		--kubernetes-version "$INT_KVERS"
	fi

	print_header 'Finished installing Kubernetes - minikube and kubectl...'
}

install_build_tools() {
	print_header 'Started installing build tools...'

	cd "${GOPATH}/src/github.com/bitnami-labs/sealed-secrets" || exit 2

	go build -i ./...

	echo "Installing build tools..."
	apt install -y \
		gcc \
		make
	go get github.com/google/go-jsonnet/cmd/jsonnet
	go get github.com/onsi/ginkgo/ginkgo

	echo "Cleaning working dir of previous artifacts..."
	make clean
	rm -r "ksonnet-lib"

	echo "Fetching go sources..."
	# git clone https://github.com/ksonnet/ksonnet-lib "${GOPATH}"/src/github.com/ksonnet/ksonnet-lib
	# go get github.com/bitnami/kubecfg

	echo "Installing kubecfg..."
	v=0.8.0
	if ! which kubecfg-$v; then
	  wget -q -O "$GOPATH/bin/kubecfg-$v" "https://github.com/ksonnet/kubecfg/releases/download/v$v/kubecfg-$(go env GOOS)-$(go env GOARCH)"
	  chmod +x "$GOPATH/bin/kubecfg-$v"
	fi
	ln -sf "kubecfg-$v" "$GOPATH/bin/kubecfg"
	git clone --depth=1 https://github.com/ksonnet/ksonnet-lib.git
	export KUBECFG_JPATH=$PWD/ksonnet-lib

	print_header 'Finished installing build tools...'
}

function test_sealed_secrets() {
	print_header 'Started Sealed Secrets Script Jobs...'

	make
	make test

	echo "Check GO version and run make vet..."
	if [[ ${TRAVIS_GO_VERSION}.0 =~ ^1\.10\. ]]; then make vet; fi
	make kubeseal-static
	EXE_NAME=kubeseal-$(go env GOOS)-$(go env GOARCH)
	cp kubeseal-static "$EXE_NAME"
	"./$EXE_NAME" --help || test $? -eq 2

	echo "Check OS is Linux and make controller.yaml..."
	if [ "$TRAVIS_OS_NAME" = linux ]; then
	  make controller.yaml controller-norbac.yaml "CONTROLLER_IMAGE=$CONTROLLER_IMAGE"
	  sed -i 's/imagePullPolicy: Always/imagePullPolicy: Never/g' "$INT_SSC_CONF"
	fi

	echo "Check Kubernetes defined and make integrationtest..."
	if [ "$INT_KVERS" != "" ]; then
	  minikube update-context
	  minikube status
	  while ! kubectl cluster-info; do sleep 3; done
	  kubectl create -f "$INT_SSC_CONF"
	  kubectl rollout status deployment/sealed-secrets-controller -n kube-system -w
	  make integrationtest "CONTROLLER_IMAGE=$CONTROLLER_IMAGE"
	fi

	print_header 'Finished Sealed Secrets Script Jobs...'
}

function print_header() {
	echo "
	###################################################################
	## $1
	###################################################################"
}

main() {

	apt update
	setup_env
	install_go
	install_kubernetes
	install_build_tools
	test_sealed_secrets

	echo "All build and test processes completed successfully."

}

main "$@"

