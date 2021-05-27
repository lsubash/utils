# BKC

## Build

### `tpm-devel` container image

Followed steps listed in this link to create `tpm-devel` container image

https://github.com/intel-secl/tpm-provider/blob/master/doc/build.md

### pull repository

```shell
git clone
```

### start a one time docker container with shell

```shell
cd bkc
docker run -v `pwd`:/docker_host -v ~/.ssh:/root/.ssh -v ~/.gitconfig:/root/.gitconfig -it --rm tpm-devel /bin/bash
```

### build installer from the container

```shell
cd /docker_host
make all
```

