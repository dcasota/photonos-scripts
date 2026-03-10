# Integration Guide: `tdnf depgraph`

This document describes exactly how to integrate the depgraph extension
into the vmware/tdnf source tree.

## New Files to Add

| Destination in tdnf tree | Source in this directory |
|---|---|
| `solv/tdnfdepgraph.c` | `solv_tdnfdepgraph.c` |
| `client/depgraph.c` | `client_depgraph.c` |
| `tools/cli/lib/depgraph.c` | `cli_depgraph.c` |

## Modifications to Existing Files

### 1. `include/tdnftypes.h`

Append the contents of `tdnftypes_depgraph.h` before the closing:
```c
#ifdef __cplusplus
}
#endif
```

### 2. `include/tdnf.h`

Append the contents of `tdnf_depgraph_api.h` (includes `TDNFDepGraph` and `TDNFFreeDepGraph`)
before the closing:
```c
#ifdef __cplusplus
}
#endif
```

### 3. `include/tdnfcli.h`

Append the contents of `tdnfcli_depgraph.h` before the closing:
```c
#ifdef __cplusplus
}
#endif
```

### 4. `solv/prototypes.h`

Append the contents of `solv_prototypes_depgraph.h` before the closing:
```c
#ifdef __cplusplus
}
#endif
```

### 5. `solv/CMakeLists.txt`

Add `tdnfdepgraph.c` to the source list:
```cmake
add_library(${LIB_TDNF_SOLV} STATIC
    tdnfpackage.c
    tdnfpool.c
    tdnfquery.c
    tdnfrepo.c
    simplequery.c
    tdnfdepgraph.c          # <-- ADD THIS LINE
)
```

### 6. `client/CMakeLists.txt`

Add `depgraph.c` to the source list:
```cmake
add_library(${LIB_TDNF} SHARED
    api.c
    client.c
    config.c
    eventdata.c
    goal.c
    gpgcheck.c
    init.c
    packageutils.c
    plugins.c
    repo.c
    repoutils.c
    remoterepo.c
    repolist.c
    resolve.c
    rpmtrans.c
    updateinfo.c
    utils.c
    history.c
    varsdir.c
    depgraph.c               # <-- ADD THIS LINE
)
```

### 7. `tools/cli/lib/CMakeLists.txt`

Add `depgraph.c` to the source list:
```cmake
add_library(${LIB_TDNF_CLI} SHARED
    api.c
    help.c
    installcmd.c
    options.c
    output.c
    parseargs.c
    parsecleanargs.c
    parselistargs.c
    parsehistoryargs.c
    parserepolistargs.c
    parserepoqueryargs.c
    parsereposyncargs.c
    parseupdateinfo.c
    updateinfocmd.c
    depgraph.c               # <-- ADD THIS LINE
)
```

### 8. `tools/cli/main.c`

Add the depgraph entry to the command dispatch table `arCmdMap[]`:
```c
static TDNF_CLI_CMD_MAP arCmdMap[] =
{
    {"autoerase",          TDNFCliAutoEraseCommand, true},
    ...
    {"count",              TDNFCliCountCommand, false},
    {"depgraph",           TDNFCliDepGraphCommand, false},   // <-- ADD THIS LINE
    {"distro-sync",        TDNFCliDistroSyncCommand, true},
    ...
};
```

### 9. `tools/cli/lib/help.c`

Add depgraph to the help text (in the "List of Main Commands" section):
```c
"depgraph               Export the full RPM dependency graph\n"
"                           Example: tdnf depgraph --json > deps.json\n"
"                           Example: tdnf depgraph --dot | dot -Tsvg -o deps.svg\n"
```

### 10. `tools/cli/lib/parseargs.c`

Add the `--dot` option to the `pstOptions[]` array:
```c
    // depgraph options
    {"dot",           no_argument, 0, 0},
```

## Build and Test

```bash
cd tdnf
mkdir build && cd build
cmake ..
make

# Test: adjacency list (current system)
./bin/tdnf depgraph

# Test: JSON with branch metadata
./bin/tdnf depgraph --json --setopt branch=5.0 > /tmp/depgraph-5.0.json

# Test: per-branch via --releasever
./bin/tdnf depgraph --json --releasever=3.0 --setopt branch=3.0 > /tmp/depgraph-3.0.json
./bin/tdnf depgraph --json --releasever=4.0 --setopt branch=4.0 > /tmp/depgraph-4.0.json

# Test: DOT with branch label
./bin/tdnf depgraph dot --setopt branch=5.0 > /tmp/depgraph-5.0.dot

# Test: 6.0 from local build RPMS
./bin/tdnf depgraph --json -c /path/to/tdnf-6.0.conf --setopt branch=6.0 > /tmp/depgraph-6.0.json
```
