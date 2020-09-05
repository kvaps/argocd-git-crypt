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
   gpg: key 8CB8B24F50B4797D marked as ultimately trusted
   gpg: directory '/home/argocd/.gnupg/openpgp-revocs.d' created
   gpg: revocation certificate stored as '/home/argocd/.gnupg/openpgp-revocs.d/9A1FF8CAA917CE876E2562FC8CB8B24F50B4797D.rev'
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
         9A1FF8CAA917CE876E2562FC8CB8B24F50B4797D
   uid           [ultimate] YOUR NAME <YOUR EMAIL@example.com>
   sub   rsa3072 2020-09-04 [E]

   $ gpg --armor --export-secret-keys 8CB8B24F50B4797D
   ```
   
   Save the key output

3. Add key to argocd-gpg-keys-cm configmap:

   ```yaml
   $ kubectl -n argocd edit cm argocd-gpg-keys-cm
   apiVersion: v1
   data:
     8CB8B24F50B4797D: |-
       -----BEGIN PGP PRIVATE KEY BLOCK-----
       
       lQVYBF9Q8KUBDACuS4p0ctXoakPLqE99YLmdixfF/QIvXVIG5uBXClWhWMuo+D0c
       ZfeyC5GvH7XPUKz1cLMqL6o/u9oHJVUmrvN/g2Mnm365nTGw1M56AfATS9IBp0HH
       O/fbfiH6aMWmPrW8XIA0icoOAdP+bPcBqM4HRo4ssbRS9y/i
       =yj11
       -----END PGP PRIVATE KEY BLOCK-----
   ```
   *Alternative, but more **secure way**, might be to create the secret*:
   
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: argocd-gpg-keys-secret
     namespace: argocd
   stringData:
     8CB8B24F50B4797D: |-
       -----BEGIN PGP PRIVATE KEY BLOCK-----
       
       lQVYBF9Q8KUBDACuS4p0ctXoakPLqE99YLmdixfF/QIvXVIG5uBXClWhWMuo+D0c
       ZfeyC5GvH7XPUKz1cLMqL6o/u9oHJVUmrvN/g2Mnm365nTGw1M56AfATS9IBp0HH
       O/fbfiH6aMWmPrW8XIA0icoOAdP+bPcBqM4HRo4ssbRS9y/i
       =yj11
       -----END PGP PRIVATE KEY BLOCK-----
   ```
   and modify the gpg-keys volume in argocd-repo-server deployment to have them projected:

   ```yaml
   $ kubectl edit deploy/argocd-repo-server
   spec:
     template:
       spec:
         volumes:
         - name: gpg-keys
           projected:
             defaultMode: 420
             sources:
             - secret:
                 name: argocd-gpg-keys-secret
             - configMap:
                 name: argocd-gpg-keys-cm
   ```


4. Verify the Installation:
   
   After setting the key it should apears in argo key storage, you can check this simple:

   ```console
   $ kubectl exec -ti deploy/argocd-repo-server -- bash
   $ GNUPGHOME=/app/config/gpg/keys gpg --list-secret-keys
   gpg: WARNING: unsafe ownership on homedir '/app/config/gpg/keys'
   /app/config/gpg/keys/pubring.kbx
   --------------------------------
   sec   rsa2048 2020-09-05 [SC] [expires: 2021-03-04]
         ED6285A3B1A50B6F1D9C955E5E8B1B16D47FFC28
   uid           [ultimate] Anon Ymous (ArgoCD key signing key) <noreply@argoproj.io>
   
   sec   rsa3072 2020-09-03 [SC]
         9A1FF8CAA917CE876E2562FC8CB8B24F50B4797D
   uid           [ultimate] YOUR NAME <YOUR EMAIL@example.com>
   ssb   rsa3072 2020-09-03 [E]
   ```


### Usage:

1. Import the key:

    ```console
    $ gpg --import 8CB8B24F50B4797D.key
    ```

2. Trust the key:

    ```console
    $ gpg --edit-key 8CB8B24F50B4797D
    trust
    5
    ```

3. Add argo as collaborator to your git project:

    ```console
    $ git-crypt add-gpg-user 8CB8B24F50B4797D
    ```
