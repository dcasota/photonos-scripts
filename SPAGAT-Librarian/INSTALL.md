# INSTALL

SPAGAT-Librarian CLI ships as a single C binary called `spagat-librarian`.
It has three build paths on a plain Linux host: from source with `make`,
from source with `cmake`, or from an RPM built via `spagat.spec`.

## Dependencies

| Package             | Runtime | Build    | Notes                                       |
| ------------------- | ------- | -------- | ------------------------------------------- |
| `ncurses`           | yes     | headers  | TUI                                         |
| `sqlite3`           | yes     | headers  | Kanban store (`~/.spagat.db` by default)    |
| `gcc` and `make`    |         | required | Native build                                |
| `cmake` (3.20+)     |         | optional | Alternate build path                        |
| `llama.cpp`         | opt.    | opt.     | Only needed for the offline local-LLM path  |
| `rpm-build`         |         | opt.     | Only needed when building the RPM           |

The offline LLM path is optional. If you plan to use only a frontier LLM
(Anthropic / Gemini / xAI / OpenAI) via environment-variable keys, you
can skip `llama.cpp` entirely.

### Photon OS 5.0

```bash
sudo tdnf install -y gcc make ncurses-devel sqlite-devel
# optional, for offline LLM:
sudo tdnf install -y cmake git
```

### Fedora

```bash
sudo dnf install -y gcc make ncurses-devel sqlite-devel
# optional:
sudo dnf install -y cmake git
```

### Debian and Ubuntu

```bash
sudo apt-get install -y build-essential libncurses-dev libsqlite3-dev
# optional:
sudo apt-get install -y cmake git
```

## Native build

From the repository root (the sources live in `SPAGAT-Librarian/`):

```bash
make -C SPAGAT-Librarian            # default target: release
# binary produced at: SPAGAT-Librarian/spagat-librarian
```

`make -C SPAGAT-Librarian debug` builds with debug flags instead.

Install into `/usr/bin` (`DESTDIR` is honoured for staged installs):

```bash
sudo make -C SPAGAT-Librarian install
```

## CMake build

```bash
cmake -B build -S SPAGAT-Librarian -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
sudo cmake --install build
```

## RPM build

The source ships an `spagat.spec` for Photon OS, Fedora, or any RPM-based
distro:

`spagat.spec` expects `Source0` (`spagat-librarian-<version>.tar.gz`) in
`~/rpmbuild/SOURCES/`; create the tarball from `SPAGAT-Librarian/` first.

```bash
rpmbuild -ba SPAGAT-Librarian/spagat.spec
sudo rpm -Uvh ~/rpmbuild/RPMS/x86_64/spagat-librarian-*.rpm
```

The RPM installs the binary at `/usr/bin/spagat-librarian` and the eight
default skill files into the shared data directory (see
[SKILLS.md](SKILLS.md)).

## Optional: offline LLM (llama.cpp)

If you want an offline LLM path, build or install `llama.cpp` separately
and download a GGUF model. Point SPAGAT-Librarian at both via the
environment variables documented in [CONFIGURATION.md](CONFIGURATION.md).
No further build wiring is needed — the C binary loads the local backend
lazily at first LLM request.

## Verified platforms

| Platform            | Native build | RPM build | Notes                        |
| ------------------- | ------------ | --------- | ---------------------------- |
| Photon OS 5.0       | yes          | yes       | Reference build target       |
| Fedora 40 / 41      | yes          | yes       |                              |
| Debian 12 / Ubuntu  | yes          | via alien | `make` path is the tested one |

## Verifying the install

```bash
spagat-librarian --version
spagat-librarian --help
spagat-librarian init      # creates $XDG_STATE_HOME/spagat/spagat.db
spagat-librarian           # opens the TUI
```

If the TUI opens on an empty board and `--version` prints a version
string, you are done. Move on to [CONFIGURATION.md](CONFIGURATION.md) to
wire up the LLM.
