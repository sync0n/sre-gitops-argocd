.PHONY: setup argocd-ui app-forward clean

setup:
	@bash bootstrap/bootstrap.sh

argocd-ui:
	@kubectl port-forward svc/argocd-server -n argocd 8080:80

app-forward:
	@kubectl port-forward svc/app -n app 8888:80

clean:
	@kind delete cluster --name gitops-cluster
