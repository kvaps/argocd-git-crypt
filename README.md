# argocd-git-crypt


This is an attempt to implement transparent PGP encryption support for ArgoCD using git-crypt.

### preambular

The following docker image contains [small wrapper script](git) for git to automatically unlock repository after fetching using git-crypt.

### Installation:

Update your deploy/argocd-repo-server

    kubectl -n argocd set image deploy/argocd-repo-server argocd-repo-server=kvaps/argocd-git-crypt@sha256:4e3f7a62e65d6ab61619d1f895f7b01abf8c8b85cba67fb6147076badd1afbb0

### Configuration

See [#git-crypt](#git-crypt) section or read the [original post](https://itnext.io/configure-custom-tooling-in-argo-cd-a4948d95626e):  
*(I present its contents below)*

---

# Configure Custom Tooling in Argo CD

Some time after writing the [first article](https://itnext.io/trying-new-tools-for-building-and-automate-the-deployment-in-kubernetes-f96f9684e580), where I cleverly use jsonnet and gitlab, I realized that pipelines are certainly good, but unnecessarily difficult and inconvenient.

In most cases, a typical task is need: “to generate YAML and put it in Kubernetes”. Actually, this is what the Argo CD does really well.

Argo CD allows you to connect a Git repository and sync its state to Kubernetes. By default several types of applications are supported: Kustomize, Helm charts, Ksonnet, raw Jsonnet or simple directories with YAML/JSON manifests.

Most users will be happy for having just this tool set, but not everyone. In order to satisfy the needs of anyone, Argo CD has the ability to use custom tooling.

First of all, I was interested in the opportunity to add support for [qbec](https://itnext.io/trying-new-tools-for-building-and-automate-the-deployment-in-kubernetes-f96f9684e580#4c4b) and [git-crypt](https://itnext.io/trying-new-tools-for-building-and-automate-the-deployment-in-kubernetes-f96f9684e580#29ed), which were fully discussed in the previous article.

Before start the configuration, we need first understand how the Argo CD works.
For each app added, it has two phases:

* **init** —initial preparation before deployment, anything can be here: dependencies download, unpacking secrets, and so on.

* **generate** — executing the command for generating manifests, the output must be a valid YAML stream, this is exactly what will be applied to the cluster.

Notably that Argo applies this approach to any type of application, including Helm. Thus in Argo CD Helm is not deploying any releases to a cluster, instead it is used to generate the manifests only.

From other side Argo is able to handle Helm hooks natively, which allows to not break the logic of applying releases.

## QBEC

Qbec allows you to conveniently describe applications using jsonnet, and besides, it has the ability to render Helm charts, and since Argo CD can handle Helm hooks, using this feature with Argo CD allows you to achieve even more correct result.

In order to add qbec support to argocd, you need two things:

* your Argo CD config must contain custom plugin definitionwith specific commands for generating manifests.

* the required binaries must be available in the **argocd-repo-server** image.

The first task is [solved](https://argoproj.github.io/argo-cd/user-guide/config-management-plugins/) quite simply:

    # cm.yaml
    data:
      configManagementPlugins: |
        - name: qbec
          generate:
            command: [sh, -xc]
            args: ['qbec show "$ENVIRONMENT" -S --force:k8s-namespace "$ARGOCD_APP_NAMESPACE"']

*(command **init** is not used)*

    $ kubectl -n argocd patch cm/argocd-cm -p "$(cat cm.yaml)"

To add binaries, it is proposed to build a new image, or use the [trick with the init-container](https://argoproj.github.io/argo-cd/operator-manual/custom_tools/#adding-tools-via-volume-mounts):

    # deploy.yaml
    spec:
      template:
        spec:
          # 1. Define an emptyDir volume which will hold the custom binaries
          volumes:
          - name: custom-tools
            emptyDir: {}
          # 2. Use an init container to download/copy custom binaries into the emptyDir
          initContainers:
          - name: download-tools
            image: alpine:3.12
            command: [sh, -c]
            args:
            - wget -qO- https://github.com/splunk/qbec/releases/download/v0.12.2/qbec-linux-amd64.tar.gz | tar -xvzf - -C /custom-tools/
            volumeMounts:
            - mountPath: /custom-tools
              name: custom-tools
          # 3. Volume mount the custom binary to the bin directory (overriding the existing version)
          containers:
          - name: argocd-repo-server
            volumeMounts:
            - mountPath: /usr/local/bin/qbec
              name: custom-tools
              subPath: qbec
            - mountPath: /usr/local/bin/jsonnet-qbec
              name: custom-tools
              subPath: jsonnet-qbec

    $ kubectl -n argocd patch deploy/argocd-repo-server -p "$(cat deploy.yaml)"

Now let’s see how the manifest of our application will look like:

    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: qbec-app
      namespace: argocd
    spec:
      destination: 
        namespace: default
        server: [https://kubernetes.default.svc](https://kubernetes.default.svc)
      project: default
      source: 
        path: examples/test-app
        targetRevision: fix-example
        plugin: 
          env: 
            - name: ENVIRONMENT
              value: dev
          name: qbec
        repoURL: [https://github.com/kvaps/qbec](https://github.com/kvaps/qbec)
      syncPolicy: 
        automated: 
          prune: true

The ENVIRONMENT variable contains the name of environment for which we need to generate manifests.

apply and see what we get:

![](https://cdn-images-1.medium.com/max/3600/0*drkPpgDHwOWYZIA2.png)

the app is up and running, great!

## git-crypt

Git-crypt allows you to set up transparent encryption of the repository. This is an easy and secure way to store sensitive data right in git.

The git-crypt implementation turned out to be more difficult.
In theory, we could run git-crypt unlock at the init stage of our custom plugin, but this is not very convenient, since it would not allow to use native deployment methods. For example, in the case of Helm and Jsonnet, we lose a flexible GUI interface which simplify the application configuration (values ​​files, etc.).
That is why I wanted to unseal the repository even on earlier stage, during the clone.

Since at the moment Argo CD does not provide the ability to describe any hooks for synchronizing the repository, I had to bypass this limitation using a tricky shell script that wraps the git command:

    #!/bin/sh
    $(dirname $0)/git.bin "$@"
    ec=$?
    [ "$1" = fetch ] && [ -d .git-crypt ] || exit $ec
    GNUPGHOME=/app/config/gpg/keys git-crypt unlock 2>/dev/null
    exit $ec

Argo CD runs git fetch every time before the deployment operation. Exaclty this command I used to handle the execution of **git-crypt unlock** to unlock the repository.

for tests, you can use my docker image, which is already has everything need:

    $ kubectl -n argocd set image deploy/argocd-repo-server argocd-repo-server=docker.io/kvaps/argocd-git-crypt:v1.7.3

Now we need to think about how Argo will decrypt repositories.

Let’s generate a gpg key for it:

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

Save the key name 8CB8B24F50B4797D for further steps, then export the key itself:

    $ gpg --list-keys
    gpg: WARNING: unsafe ownership on homedir '/home/argocd/.gnupg'
    /home/argocd/.gnupg/pubring.kbx
    -------------------------------
    pub   rsa3072 2020-09-04 [SC]
          9A1FF8CAA917CE876E2562FC8CB8B24F50B4797D
    uid           [ultimate] YOUR NAME <YOUR EMAIL@example.com>
    sub   rsa3072 2020-09-04 [E]

    $ gpg --armor --export-secret-keys 8CB8B24F50B4797D

And add it as a separate secret:

    # argocd-gpg-keys-secret.yaml
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

    $ kubectl apply -f argocd-gpg-keys-secret.yaml

The only thing left is to connect it to the **argocd-repo-server** container, to achieve this edit the deployment:

    $ kubectl -n argocd edit deploy/argocd-repo-server

And replace existing **gpg-keys** volume type to projected, and specify our secret there:

    spec:
      template:
        spec:
          volumes:
          - name: gpg-keys
            projected:
              sources:
              - secret:
                name: argocd-gpg-keys-secret
              - configMap:
                name: argocd-gpg-keys-cm

Argo CD automatically loads gpg keys from this directory during the startup, so it loads our private key as well.

let’s check:

    $ kubectl -n argocd exec -ti deploy/argocd-repo-server -- bash
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

Great, the key is loaded! Now we only need to add Argo CD as a collaborator to our repository. This will enable automatic decryption on the fly.

Import the key to the local computer:

    $ GNUPGHOME=/app/config/gpg/keys gpg --armor --export 8CB8B24F50B4797D > 8CB8B24F50B4797D.pem
    $ gpg --import 8CB8B24F50B4797D.pem

Trust the key:

    $ gpg --edit-key 8CB8B24F50B4797D
    trust
    5

Add argo as collaborator to your git project:

    $ git-crypt add-gpg-user 8CB8B24F50B4797D

**Related links**:

* [GitHub: repository with modified image](http://github.com/kvaps/argocd-git-crypt)

* [Argo CD: Custom Tooling](https://argoproj.github.io/argo-cd/operator-manual/custom_tools/)

* [Argo CD: Config Management Plugins](https://argoproj.github.io/argo-cd/user-guide/config-management-plugins/)

* [GitHub Gist: generate gpg key via batch file](https://gist.github.com/vrillusions/5484422)
