Recommend not reviewing this until you have attempted all of the labs.

The commands shown in the "solutions" are `kubectl` commands, but
corresponding `k9s` commands could be used instead.

# LAB1

## Deployment 1

In this deployment, there is a typo in the image for the container name
used for the deployment. 

To see this mistake, run `kubectl describe pod -n debugging <pod-name>`

You will see an error similar to 

```
  Warning  Failed     2m56s (x5 over 5m51s)  kubelet            spec.containers{pause}: Failed to pull image "registry.kBs.io/pause:3.9": failed to pull and unpack image "registry.kBs.io/pause:3.9": failed to resolve reference "registry.kBs.io/pause:3.9": failed to do request: Head "https://registry.kBs.io/v2/pause/manifests/3.9": remote error: tls: unrecognized name
```

Note that there is an image pull error. Look closely at the image and recognize
there is likely a typo `Failed to pull image "registry.kBs.io/pause:3.9"`

Edit the deployment1.yaml file to have the image name of
`registry.k8s.io/pause:3.9` replacing the *B* with an *8*.
Wait for the deployment to restart the pod, and watch it pull successfully.

## Deployment 2

## Deployment 3

# LAB2

## Deployment 4

## Deployment 5

## Deployment 6

# LAB3

## Deployment 7

# LAB4

## Deployment 8

