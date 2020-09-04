# argocd-git-crypt (PoC)

This is an attempt to implement transparent PGP encryption support for ArgoCD using git-crypt.

### Principle of operation

The following patch is adding additional sidecar container to argocd-repo-server, which is watching for new git repositories apearing and automatically unlock them using git-crypt.

### Limitations

This project is just Proof-of-concept, it is working but still have some disadvantages:

- inotify is used to watch for created repos which is not optimal
- race condition between argo, which might break initial repo synchronisation.

### Installation:

1. Generate gpg-key without passphrase

   * https://gist.github.com/vrillusions/5484422

2. Export key to file:

       gpg --export-secret-keys 9A1FF8CAA917CE876E2562FC8CB8B24F50B4797D > argo.key

3. Create secret:

       kubectl create secret generic argocd-gpg-secrets --from-file argo.key

4. Install the patch:

       curl -LO https://github.com/kvaps/argocd-git-crypt/raw/master/deploy.yaml
       kubectl patch  deploy/argocd-repo-server -p "$(cat deploy.yaml)"

### Usage:

1. Trust the key:

       gpg --edit-key 8CB8B24F50B4797D
       > trust
       > 5

2. Add argo as collaborator to your git project:

       git-crypt add-gpg-user 8CB8B24F50B4797D
