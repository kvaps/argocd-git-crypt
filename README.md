# argocd-git-crypt

This is an attempt to implement transparent PGP encryption support for ArgoCD using git-crypt.

### preambular

The following docker image contains [small wrapper script](git) for git to automatically unlock repository after fetching using git-crypt.

### Installation:

Update your deploy/argocd-repo-server

    kubectl -n argocd set image deploy/argocd-repo-server argocd-repo-server=kvaps/argocd-git-crypt@sha256:4e3f7a62e65d6ab61619d1f895f7b01abf8c8b85cba67fb6147076badd1afbb0

### Configuration

1. Generate gpg-key without passphrase:

   ```console
   $ kubectl exec -ti deploy/argocd-repo-server -- bash

   $ printf "%s\n" \
       "%no-protection" \
       "Key-Type: default" \
       "Subkey-Type: default" \
       "Name-Real: YOUR NAME" \
       "Name-Email: YOUR EMAIL@example.com" \
       "Expire-Date: 0" \
       > genkey-batch 

   $ gpg --batch --gen-key genkey-batch
   gpg: WARNING: unsafe ownership on homedir '/home/argocd/.gnupg'
   gpg: keybox '/home/argocd/.gnupg/pubring.kbx' created
   gpg: /home/argocd/.gnupg/trustdb.gpg: trustdb created
   gpg: key B49D6D5A0D55FF9D marked as ultimately trusted
   gpg: directory '/home/argocd/.gnupg/openpgp-revocs.d' created
   gpg: revocation certificate stored as '/home/argocd/.gnupg/openpgp-revocs.d/2E6D458745B33DDC6EB0D452B49D6D5A0D55FF9D.rev'
   ```
       
   Save the key name from the output

   *(see https://gist.github.com/vrillusions/5484422 for more details)*

2. Export key to file:

   ```console
   $ gpg --list-keys
   gpg: WARNING: unsafe ownership on homedir '/home/argocd/.gnupg'
   /home/argocd/.gnupg/pubring.kbx
   -------------------------------
   pub   rsa3072 2020-09-04 [SC]
         2E6D458745B33DDC6EB0D452B49D6D5A0D55FF9D
   uid           [ultimate] YOUR NAME <YOUR EMAIL@example.com>
   sub   rsa3072 2020-09-04 [E]

   $ gpg --armor --export-secret-keys B49D6D5A0D55FF9D | base64 -w0; echo
   ```
   
   Save the output base64 string

3. Add key to configmap:

   ```console
   $ kubectl -n argocd edit cm argocd-gpg-keys-cm
   apiVersion: v1
   data:
     B49D6D5A0D55FF9D: |-
     -----BEGIN PGP PRIVATE KEY BLOCK-----
     
     lQVYBF9SujoBDADTz3Qi8XuEXVIxx5uJyutyFLQw6XSG0dSL379cnb9A6oM59l2a
     RJl7WBxxDFNnj7K3r/4I9KFxTrTp8P+q5BVUZikoogw8mEgwK+7krynrY6a2/Tda
     Hn8ZTpZ0aKeqew+hRH/R5GWePDrhaBQp1IYAdq8OQbwzNsoeR6iS6m8rl++q7BKN
     ...
   ```

### Usage:

1. Import the key:

    ```console
    $ gpg --import B49D6D5A0D55FF9D.key
    ```

2. Trust the key:

    ```console
    $ gpg --edit-key B49D6D5A0D55FF9D
    trust
    5
    ```

3. Add argo as collaborator to your git project:

    ```console
    $ git-crypt add-gpg-user B49D6D5A0D55FF9D
    ```
