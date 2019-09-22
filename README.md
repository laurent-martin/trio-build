# trio-build
This script creates an environment to build debian package for:

- libpthsem
- linknx
- knxd
- knxweb

# Usage
Display samples:
```bash
$ build_trio.sh
```

`build_deb libpthsem archive` build libpthsem from archive

`libpthsem_install_dev` install required packages for compilation

`build_deb linknx archive` build linknx package from archive

`build_deb knxd git` build knxd package from git

`build_deb knxweb git` build knxweb package from git

`install_all` builds all
