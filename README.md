
gpg --export-secret-keys 9A1FF8CAA917CE876E2562FC8CB8B24F50B4797D | base64 -w0; echo
gpg --export 9A1FF8CAA917CE876E2562FC8CB8B24F50B4797D | base64 -w0; echo

https://gist.github.com/vrillusions/5484422
gpg --export-secret-keys  > 1.key
gpg --import 1.key



gpg --edit-key 8CB8B24F50B4797D


kubectl create secret generic argocd-gpg-secrets --from-file argo.key
kubectl patch  deploy/argocd-repo-server -p "$(cat deploy.yaml)"
