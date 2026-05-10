# Package Classifier — Branch dev

_Generated: 2026-05-10T22:54:49+00:00_  
_Records considered (this branch): 1817; deduplicated: 10 of top 10_  

### 1. go — composite_score 96.4
[https://go.dev](https://go.dev)  
**Resume:** The Go programming language and toolchain.

### 2. python-pydantic — composite_score 93.8
[https://pydantic.dev](https://pydantic.dev)  
**Resume:** Data validation and settings management using Python type annotations.

### 3. python-pytest — composite_score 93.8
[https://docs.pytest.org/](https://docs.pytest.org/)  
**Resume:** Python testing framework that makes it easy to write, organize and run tests with fixtures and plugins.

### 4. python-numpy — composite_score 93.2
[https://numpy.org/](https://numpy.org/)  
**Resume:** Fundamental package for scientific computing with Python, providing multi-dimensional arrays and mathematical functions.

### 5. git — composite_score 93.1
[https://git-scm.com](https://git-scm.com)  
**Resume:** Distributed version control system for tracking source code changes during software development.

### 6. python3 — composite_score 93.1
[https://www.python.org/](https://www.python.org/)  
**Resume:** Core Python programming language distribution (interpreter and standard library).

### 7. coreutils — composite_score 92.8
[https://www.gnu.org/software/coreutils/](https://www.gnu.org/software/coreutils/)  
**Resume:** GNU collection of basic file, shell and text manipulation utilities (ls, cp, cat, etc.).

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | uutils-coreutils | 89.4 | Direct functional CLI replacement providing the same utilities with compatible command-line behavior. |

### 8. rubygem-nokogiri — composite_score 92.5
[https://nokogiri.org/](https://nokogiri.org/)  
**Resume:** Nokogiri is an HTML, XML, SAX, and Reader parser with XPath and CSS selector support.

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | ox | 84.8 | Direct drop-in XML/HTML parser replacement for Nokogiri use cases with comparable Ruby APIs. |
| 2 | oga | 81.2 | Pure-Ruby XML/HTML parser that can replace Nokogiri for parsing and querying without native deps. |

### 9. filesystem — composite_score 92.5
[http://www.linuxfromscratch.org](http://www.linuxfromscratch.org)  
**Resume:** Instructions for building a complete Linux system from source code.

### 10. google-benchmark — composite_score 92.4
[https://github.com/google/benchmark](https://github.com/google/benchmark)  
**Resume:** Microbenchmark support library for C++

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | nanobench | 88.3 | Direct drop-in microbenchmarking replacement with similar API for timing C++ code snippets. |
| 2 | celero | 81.0 | Functional replacement providing comparable C++ microbenchmark harness and reporting. |

## Alternatives outscoring the package

_296 alternative(s) score higher than the corresponding package._

| # | Package | Pkg score | Alternative | Alt score | Δ | Rationale |
|---|---|---|---|---|---|---|
| 1 | commons-httpclient | 35.5 | OkHttp | 89.0 | +53.5 | Widely adopted modern HTTP client usable as direct replacement for classic sync calls. |
| 2 | commons-httpclient | 35.5 | Apache HttpComponents Client | 86.2 | +50.7 | Official successor maintaining similar request/response API and configuration model. |
| 3 | python-ipaddr | 45.5 | ipaddress | 89.9 | +44.4 | Direct stdlib successor with equivalent IP parsing/validation primitives |
| 4 | python-vcversioner | 45.5 | setuptools-scm | 89.8 | +44.3 | Direct functional replacement: same VCS-tag-to-PEP440 version extraction at build time, same Python runtime, sync usage pattern, actively m… |
| 5 | rubygem-hpricot | 45.5 | nokogiri | 88.1 | +42.6 | Nokogiri provides the same HTML parsing and traversal capabilities with near-identical usage patterns and is the standard replacement for h… |
| 6 | rubygem-zip | 41.0 | rubyzip | 82.8 | +41.8 | Provides near-identical Zip::ZipFile and entry handling APIs as a modern, maintained drop-in for the legacy zip gem. |
| 7 | mingetty | 41.5 | agetty | 83.2 | +41.7 | agetty provides identical console login prompt functionality and is the standard replacement shipped in util-linux, requiring only config p… |
| 8 | log4cpp | 52.5 | spdlog | 93.4 | +40.9 | Direct functional replacement providing equivalent logger configuration and output sinks with simpler modern API. |
| 9 | perl-WWW-Curl | 48.5 | HTTP::Tiny | 89.2 | +40.7 | Direct Perl HTTP client replacement; same sync API style, no external libs needed. |
| 10 | cppunit | 51.5 | GoogleTest | 92.2 | +40.7 | Direct drop-in C++ unit testing replacement with similar test macros and runner. |
| 11 | python-lockfile | 49.5 | filelock | 90.0 | +40.5 | Direct drop-in replacement with compatible lock acquisition API and same file-based locking semantics. |
| 12 | tclap | 47.9 | CLI11 | 88.4 | +40.5 | Direct drop-in CLI parser for C++ with similar header-only usage and option handling |
| 13 | serf | 48.5 | libcurl | 88.0 | +39.5 | Direct functional replacement providing equivalent HTTP client functionality at the same C library layer with async support via curl_multi. |
| 14 | yajl | 48.5 | cJSON | 87.8 | +39.3 | Direct C JSON parsing/generation drop-in with nearly identical use cases and simpler integration. |
| 15 | nicstat | 42.5 | vnstat | 79.6 | +37.1 | Direct CLI replacement providing equivalent per-NIC byte/packet/error counters with optional persistence. |
| 16 | cppunit | 51.5 | Catch2 | 88.4 | +36.9 | Functional C++ unit testing replacement supporting same test discovery and assertions. |
| 17 | perl-Path-Class | 48.5 | Path::Tiny | 84.6 | +36.1 | Direct drop-in OO replacement providing equivalent path manipulation methods with modern Perl idioms |
| 18 | calico-bgp-daemon | 48.5 | gobgp | 83.4 | +34.9 | Direct Go BGP daemon replacement providing equivalent route advertisement and peering capabilities at the same abstraction layer. |
| 19 | perl-WWW-Curl | 48.5 | LWP::UserAgent | 82.8 | +34.3 | Widely-used Perl HTTP client with comparable request/response handling. |
| 20 | tclap | 47.9 | cxxopts | 81.9 | +34.0 | Direct functional replacement providing comparable option parsing API in C++ |
| 21 | bridge-utils | 52.5 | iproute2 | 86.2 | +33.7 | Provides identical bridge configuration functionality via the 'bridge' subcommand and is the direct in-kernel successor. |
| 22 | ebtables | 54.5 | nft | 87.2 | +32.7 | nft bridge family is the direct in-kernel successor providing identical frame-filtering capabilities via a unified CLI. |
| 23 | zip | 51.5 | 7-Zip | 84.0 | +32.5 | Direct CLI replacement for ZIP archive creation/extraction using identical file format and comparable command-line flags. |
| 24 | ivykis | 54.0 | libevent | 86.1 | +32.1 | Provides comparable event multiplexing abstraction and can replace ivykis usage patterns with minimal API adaptation in C codebases. |
| 25 | perl-Object-Accessor | 52.5 | Class::Accessor | 84.5 | +32.0 | Provides identical accessor creation API and usage pattern for Perl objects. |
| 26 | bluez-tools | 44.0 | bluetoothctl | 75.5 | +31.5 | Provides equivalent CLI commands for adapter and device management at the same BlueZ layer. |
| 27 | python-lockfile | 49.5 | fasteners | 81.0 | +31.5 | Provides equivalent inter-process file locking via InterProcessLock with minimal API changes. |
| 28 | python-vcversioner | 45.5 | dunamai | 76.2 | +30.7 | Direct functional replacement: identical VCS tag parsing to produce version strings for Python packaging, same language and sync usage. |
| 29 | rubygem-thread_safe | 58.5 | concurrent-ruby | 89.1 | +30.6 | Provides the same thread-safe maps, sets and atomic classes with compatible APIs; actively maintained successor. |
| 30 | rubygem-libxml-ruby | 57.5 | nokogiri | 87.0 | +29.5 | Direct functional replacement providing equivalent XML parsing and XPath APIs in Ruby with broader adoption and easier installation. |
| 31 | log4cpp | 52.5 | glog | 81.8 | +29.3 | Provides comparable severity-based logging and runtime configuration as a drop-in C++ logging framework. |
| 32 | python-ipaddr | 45.5 | netaddr | 74.6 | +29.1 | Actively maintained Python library providing comparable IP address handling |
| 33 | unzip | 53.5 | 7-Zip | 82.5 | +29.0 | Provides identical CLI usage pattern for ZIP extraction as a drop-in command replacement. |
| 34 | perl-Crypt-SSLeay | 48.5 | IO::Socket::SSL | 77.4 | +28.9 | Direct functional replacement providing equivalent SSL socket layer for Perl HTTP clients without code changes beyond use statements. |
| 35 | yajl | 48.5 | Jansson | 77.1 | +28.6 | Same-layer C JSON library offering comparable streaming and tree APIs for direct substitution. |
| 36 | atftp | 47.5 | tftpd-hpa | 75.8 | +28.3 | Direct functional replacement providing identical TFTP client/server CLI and daemon behavior at the same layer. |
| 37 | chrpath | 58.5 | patchelf | 86.5 | +28.0 | Direct CLI replacement for editing ELF rpath entries |
| 38 | net-tools | 51.5 | iproute2 | 79.5 | +28.0 | Provides equivalent CLI tools (ip vs ifconfig/route, ss vs netstat) at same layer with identical scripting patterns. |
| 39 | heapster | 58.5 | metrics-server | 86.4 | +27.9 | Provides identical Kubernetes metrics API surface and resource usage data collection without requiring sink reconfiguration or architecture… |
| 40 | cppunit | 51.5 | Boost.Test | 79.1 | +27.6 | Direct C++ unit testing library replacement with comparable test suite execution. |
| 41 | rapidjson | 66.5 | nlohmann/json | 94.0 | +27.5 | Direct functional replacement: same C++ header-only JSON parse/generate use cases with comparable or simpler API. |
| 42 | python-appdirs | 62.5 | platformdirs | 89.8 | +27.3 | Official successor providing the same directory-lookup functions with identical signatures and cross-platform behavior. |
| 43 | pkg-config | 58.5 | pkgconf | 85.8 | +27.3 | Direct CLI and .pc file drop-in replacement targeting identical use cases. |
| 44 | cdrkit | 52.0 | xorriso | 79.0 | +27.0 | Provides equivalent ISO creation and optical drive burning via xorriso command-line interface usable as drop-in for cdrkit tools. |
| 45 | calico-bird | 57.5 | frr | 84.4 | +26.9 | FRR provides an actively maintained BGP routing daemon binary usable in place of the Calico BIRD fork for the same IP routing use cases. |
| 46 | mlocate | 55.5 | plocate | 81.2 | +25.7 | Direct CLI-compatible replacement using the same locate/updatedb interface and database model. |
| 47 | syslinux | 53.5 | GRUB | 78.8 | +25.3 | Direct drop-in bootloader replacement handling identical boot media and kernel loading use cases. |
| 48 | python-toml | 58.5 | tomli | 83.4 | +24.9 | Direct API-compatible TOML parser used as the basis for Python 3.11+ tomllib; same load() usage pattern. |
| 49 | python-zope.event | 62.5 | blinker | 87.4 | +24.9 | Direct functional replacement providing identical publish/subscribe event pattern at same abstraction level with near-identical usage. |
| 50 | python-terminaltables | 62.5 | tabulate | 87.2 | +24.7 | Direct functional replacement: same Python table formatting API usable with minimal code changes. |
| 51 | python-ply | 58.5 | lark | 83.2 | +24.7 | Direct LALR(1) parser generator replacement with compatible grammar definitions and Python runtime usage pattern. |
| 52 | flex | 58.5 | re2c | 83.1 | +24.6 | Direct CLI lexer generator replacement targeting identical C/C++ scanner use cases with comparable output. |
| 53 | libev | 61.5 | libuv | 86.1 | +24.6 | Direct drop-in replacement providing equivalent event-loop primitives (timers, I/O watchers, async) with a comparable C API. |
| 54 | rubygem-trollop | 58.5 | slop | 83.0 | +24.5 | Direct drop-in replacement providing nearly identical option parsing DSL and usage for CLI scripts. |
| 55 | python-docopt | 62.5 | click | 86.8 | +24.3 | Direct CLI replacement: same Python runtime, actively maintained, comparable decorator-based usage for argument parsing. |
| 56 | python-docopt | 62.5 | argparse | 86.2 | +23.7 | Direct drop-in CLI parser in stdlib; solves identical argument-parsing use case without external deps. |
| 57 | nicstat | 42.5 | nload | 66.2 | +23.7 | Provides the same live per-interface throughput view via a simple terminal CLI. |
| 58 | dejavu-fonts | 55.5 | liberation-fonts | 78.8 | +23.3 | Provides drop-in TTF fonts with similar Unicode coverage and usage pattern for desktop/document rendering. |
| 59 | rubygem-multi_json | 62.5 | oj | 85.6 | +23.1 | Direct functional replacement providing identical JSON load/dump API with superior performance; users can swap via require 'oj' and Oj.mimi… |
| 60 | python-rsa | 66.5 | cryptography | 89.6 | +23.1 | Direct functional replacement providing equivalent RSA primitives with identical high-level usage patterns for encryption/signing. |
| 61 | traceroute | 62.8 | mtr | 85.7 | +22.9 | mtr directly replaces traceroute for route tracing with enhanced real-time display and identical CLI usage pattern. |
| 62 | lzo | 68.5 | LZ4 | 91.4 | +22.9 | Direct drop-in for LZO's fast compression use-cases with nearly identical C function signatures and block/stream APIs. |
| 63 | python-boto | 62.5 | boto3 | 85.1 | +22.6 | Direct official replacement providing equivalent AWS service access patterns for Python users. |
| 64 | python-incremental | 67.5 | setuptools-scm | 89.8 | +22.3 | Direct functional replacement providing automatic version inference from git tags for the same release workflow. |
| 65 | subversion | 65.5 | git | 86.8 | +21.3 | Direct CLI-based VCS replacement solving identical source-code tracking use cases with comparable commands and local repository model. |
| 66 | syslinux | 53.5 | systemd-boot | 74.5 | +21.0 | Functional UEFI bootloader swap for Syslinux's core kernel-booting functionality. |
| 67 | python-configobj | 70.5 | configparser | 91.4 | +20.9 | Direct stdlib replacement for reading/writing INI-style configs with similar dict-like API. |
| 68 | rubygem-recursive-open-struct | 67.5 | hashie | 88.4 | +20.9 | Hashie::Mash is a direct functional replacement offering the same recursive dot-notation access pattern on nested hashes. |
| 69 | lldpad | 62.5 | lldpd | 83.1 | +20.6 | Direct functional replacement: same LLDP daemon layer, C language, sync/daemon usage pattern, actively maintained and consumable. |
| 70 | rubygem-libxml-ruby | 57.5 | ox | 78.1 | +20.6 | Drop-in Ruby XML parsing library with similar low-level node access patterns and no external libxml dependency. |
| 71 | python-netifaces | 64.5 | psutil | 84.8 | +20.3 | Provides equivalent network-interface address retrieval via net_if_addrs, usable as a functional substitute in the same Python runtime. |
| 72 | pcre | 55.5 | oniguruma | 75.8 | +20.3 | Direct C regex library drop-in for Perl-compatible matching with active maintenance and comparable API patterns. |
| 73 | cscope | 55.5 | GNU Global | 75.8 | +20.3 | Provides identical symbol cross-referencing and source navigation via CLI and cscope-compatible interface. |
| 74 | python-M2Crypto | 59.5 | pyOpenSSL | 79.6 | +20.1 | Direct drop-in replacement for M2Crypto SSL/TLS and X.509 usage patterns with nearly identical high-level classes. |
| 75 | sendmail | 65.5 | postfix | 85.5 | +20.0 | Direct MTA replacement handling identical SMTP delivery and routing use cases. |
| 76 | amdvlk | 64.5 | RADV | 84.2 | +19.7 | Direct drop-in Vulkan ICD replacement for AMD hardware with identical API surface |
| 77 | rubygem-highline | 67.5 | tty-prompt | 87.2 | +19.7 | Direct functional replacement providing equivalent interactive CLI prompting and menu APIs in Ruby |
| 78 | python-terminaltables | 62.5 | prettytable | 82.2 | +19.7 | Direct functional replacement: Python library for ASCII/Unicode tables with comparable constructor and print API. |
| 79 | libnfnetlink | 62.5 | libmnl | 82.2 | +19.7 | Direct functional replacement at the same netlink abstraction layer for netfilter use cases; same C runtime and sync usage pattern. |
| 80 | libev | 61.5 | libevent | 81.2 | +19.7 | Provides the same core event-loop abstraction (event_base, watchers) and can replace libev usage patterns with minimal code changes. |
| 81 | python-imagesize | 68.5 | Pillow | 88.2 | +19.7 | Direct functional replacement: same Python runtime, sync usage pattern, returns image size tuple with comparable or lower overhead for the … |
| 82 | ntp | 64.5 | chrony | 84.1 | +19.6 | Direct functional replacement at the same daemon layer; same NTP protocol support, configuration style and deployment model as ntpd. |
| 83 | perl-JSON-Any | 59.5 | JSON::MaybeXS | 78.8 | +19.3 | Direct functional successor providing identical use-case selection of optimal JSON backend with compatible API. |
| 84 | ivykis | 54.0 | libev | 73.2 | +19.2 | Direct functional peer for async I/O multiplexing in C; same abstraction level and usage pattern for event handling. |
| 85 | perl-Module-Install | 62.5 | Dist::Zilla | 81.1 | +18.6 | Direct functional replacement for authoring and releasing Perl modules with plugin-based configuration. |
| 86 | python-typing | 68.5 | typing_extensions | 87.0 | +18.5 | Provides direct functional superset of typing backports with identical import patterns for type annotations. |
| 87 | rubygem-domain_name | 71.4 | public_suffix | 89.8 | +18.4 | Direct functional replacement providing identical Public Suffix List domain parsing and validation in Ruby. |
| 88 | cmocka | 70.5 | Unity | 88.9 | +18.4 | Lightweight C unit testing library usable as functional replacement for cmocka test cases |
| 89 | dhcp | 64.5 | kea | 82.6 | +18.1 | Official ISC replacement offering identical DHCP server functionality with improved architecture and active maintenance. |
| 90 | http-parser | 61.4 | llhttp | 79.2 | +17.8 | Official Node.js replacement offering the same C-level HTTP parsing abstraction and usage pattern. |
| 91 | python-automat | 68.5 | transitions | 86.2 | +17.7 | Direct functional replacement providing equivalent state-machine modeling via classes and decorators with minimal code changes. |
| 92 | perl-File-Remove | 70.5 | Path-Tiny | 88.2 | +17.7 | Provides direct remove() and recursive directory deletion methods matching File::Remove usage patterns in Perl. |
| 93 | pycurl | 73.5 | requests | 91.2 | +17.7 | Direct Python HTTP client replacement; same sync usage pattern and import style for basic GET/POST. |
| 94 | gflags | 70.5 | CLI11 | 88.1 | +17.6 | Direct functional replacement providing equivalent flag/option definition and parsing for C++ CLI applications. |
| 95 | python-looseversion | 68.8 | packaging | 86.4 | +17.6 | Provides equivalent version comparison functionality at the same abstraction layer with a nearly identical usage pattern for most LooseVers… |
| 96 | rubygem-httpclient | 68.5 | faraday | 85.8 | +17.3 | Direct functional replacement providing equivalent HTTP request/response handling with comparable synchronous API patterns. |
| 97 | byacc | 68.5 | bison | 85.8 | +17.3 | Direct functional replacement providing identical yacc-compatible parser generation CLI and input syntax for C users. |
| 98 | runit | 68.5 | s6 | 85.5 | +17.0 | Provides identical service supervision, logging and init functionality with compatible usage patterns and active maintenance. |
| 99 | rubygem-webrick | 70.5 | puma | 87.4 | +16.9 | Direct Rack-compatible HTTP server replacement usable in the same embedded/testing scenarios as WEBrick |
| 100 | xml-security-c | 64.0 | xmlsec | 80.9 | +16.9 | Direct C/C++ drop-in replacement providing identical XML DSig/Enc APIs and crypto provider abstraction. |
| 101 | kubernetes-dns | 72.4 | coredns/coredns | 89.2 | +16.8 | Direct drop-in cluster DNS server; same Go binary, same K8s integration points, same Corefile configuration model. |
| 102 | uwsgi | 69.8 | Gunicorn | 86.6 | +16.8 | Direct WSGI server replacement; same Python web-app deployment pattern with simpler setup. |
| 103 | python-semantic-version | 66.8 | semver | 83.6 | +16.8 | Direct functional replacement providing equivalent SemVer parsing/comparison API for Python users. |
| 104 | virt-what | 71.5 | systemd-detect-virt | 88.2 | +16.7 | Direct CLI drop-in replacement providing identical VM/container detection output. |
| 105 | vsftpd | 64.0 | Pure-FTPd | 80.4 | +16.4 | Direct functional replacement as a standalone secure FTP daemon with comparable CLI/daemon invocation and configuration style. |
| 106 | python-alabaster | 71.5 | sphinx-rtd-theme | 87.8 | +16.3 | Direct Sphinx theme replacement activated identically via html_theme config. |
| 107 | python-rsa | 66.5 | pycryptodome | 82.8 | +16.3 | Provides the same RSA operations as a drop-in module replacement with comparable synchronous usage. |
| 108 | python-pyflakes | 76.5 | ruff | 92.8 | +16.3 | Direct drop-in: ruff implements the complete Pyflakes rule set and accepts identical usage patterns for error detection. |
| 109 | gtk-doc | 55.5 | gi-docgen | 71.5 | +16.0 | Direct functional replacement used by current GNOME projects for the same C/GObject API documentation workflow. |
| 110 | lzo | 68.5 | Snappy | 84.5 | +16.0 | Provides comparable speed-focused compression/decompression suitable for replacing LZO in performance-critical paths. |
| 111 | xz | 73.5 | zstd | 89.3 | +15.8 | Direct functional drop-in for compression/decompression tasks with comparable CLI and library interfaces. |
| 112 | nss | 66.5 | openssl | 82.0 | +15.5 | Direct drop-in TLS/crypto provider; same C ABI layer, same use cases (HTTPS, cert validation). |
| 113 | lshw | 71.5 | inxi | 87.0 | +15.5 | Direct CLI drop-in replacement providing equivalent hardware enumeration output for the same Linux use cases. |
| 114 | nss-pam-ldapd | 66.5 | sssd | 81.9 | +15.4 | Direct functional replacement implementing the same NSS and PAM interfaces for LDAP directories. |
| 115 | libtdb | 67.5 | lmdb | 82.7 | +15.2 | Direct embedded KV replacement with similar C API and file-based storage model. |
| 116 | python-pytz | 70.5 | python-dateutil | 85.4 | +14.9 | Supplies equivalent tzinfo objects via dateutil.tz for the same datetime use cases with minimal import changes. |
| 117 | python-hyperlink | 68.5 | yarl | 83.4 | +14.9 | Direct functional replacement providing immutable URL objects with comparable API for parsing, building and manipulation in Python. |
| 118 | rubygem-multi_json | 62.5 | json | 77.0 | +14.5 | Provides the same JSON.parse/JSON.generate interface; multi_json users can replace by requiring 'json' directly. |
| 119 | python-mako | 77.5 | Jinja2 | 92.0 | +14.5 | Direct functional replacement as a Python templating engine with similar API and features for rendering templates. |
| 120 | pycurl | 73.5 | httpx | 87.8 | +14.3 | Sync API mirrors common pycurl patterns while remaining a drop-in HTTP client. |
| 121 | python-alabaster | 71.5 | furo | 85.6 | +14.1 | Direct Sphinx theme replacement activated identically via html_theme config. |
| 122 | ntpsec | 74.5 | chrony | 88.6 | +14.1 | Direct drop-in NTP daemon replacement with compatible configuration syntax and command-line tools for time synchronization. |
| 123 | python-yamlloader | 68.5 | ruamel.yaml | 82.5 | +14.0 | Direct functional replacement providing ordered dict loading via safe or round-trip mode without code changes beyond import. |
| 124 | lighttpd | 74.5 | nginx | 88.2 | +13.7 | Direct drop-in HTTP daemon replacement supporting identical static-file, proxy and FastCGI workloads with comparable configuration model. |
| 125 | python-setuptools-rust | 77.8 | maturin | 91.4 | +13.6 | Direct functional replacement for building Rust Python extensions; same abstraction layer and usage pattern via build backend. |
| 126 | ca-certificates | 76.0 | certdata.txt (Mozilla) | 89.5 | +13.5 | Same layer (raw CA list), identical text format and usage pattern as othercertdata.txt; actively maintained by Mozilla. |
| 127 | python-netifaces | 64.5 | ifaddr | 77.9 | +13.4 | Direct drop-in replacement providing the same interface-address lookup functionality with a compatible Python API. |
| 128 | rubygem-rdiscount | 77.5 | redcarpet | 90.8 | +13.3 | Direct drop-in Markdown renderer with compatible render API and high performance. |
| 129 | cmocka | 70.5 | Check | 83.6 | +13.1 | Direct C unit-test framework drop-in replacement providing similar test runner and assertion APIs |
| 130 | jsoncpp | 76.5 | nlohmann/json | 89.6 | +13.1 | Direct functional replacement: same C++ JSON DOM/streaming use cases, drop-in via similar parse/dump calls and value types. |
| 131 | rubygem-cool-io | 67.5 | eventmachine | 80.5 | +13.0 | Provides comparable event reactor for Ruby network I/O programs with minimal code changes for basic usage patterns |
| 132 | python-toml | 58.5 | tomlkit | 71.5 | +13.0 | Provides equivalent load/dump functions plus editing capabilities for the same TOML use cases. |
| 133 | gdbm | 70.5 | lmdb | 83.0 | +12.5 | Direct functional replacement providing comparable embedded key-value storage with similar C API usage patterns. |
| 134 | python-pycryptodomex | 76.5 | cryptography | 89.0 | +12.5 | Direct functional replacement providing equivalent low-level crypto primitives (AES, RSA, hashes, etc.) with nearly identical usage pattern… |
| 135 | python-etcd | 54.0 | etcd3 | 66.2 | +12.2 | Provides a synchronous Python client targeting the same etcd key-value operations with comparable usage patterns. |
| 136 | xz | 73.5 | lz4 | 85.6 | +12.1 | Provides equivalent lossless compression functionality via similar command-line and library usage patterns. |
| 137 | rubygem-rest-client | 76.5 | faraday | 88.4 | +11.9 | Direct drop-in Ruby HTTP client replacement with comparable request syntax and adapter flexibility. |
| 138 | check | 74.0 | unity | 85.8 | +11.8 | Minimal C unit testing replacement with comparable test macros and runner |
| 139 | python-autopep8 | 80.5 | black | 92.2 | +11.7 | Direct functional replacement providing automated Python code formatting via CLI or API with comparable usage. |
| 140 | rubygem-yajl-ruby | 78.5 | oj | 90.1 | +11.6 | Direct functional replacement providing identical JSON parse/generate calls with superior performance and maintained compatibility layer |
| 141 | systemtap | 75.5 | bpftrace | 87.0 | +11.5 | Direct CLI/scripting replacement for dynamic tracing use cases; same probe-based model on Linux without kernel modules. |
| 142 | iniparser | 76.5 | inih | 87.8 | +11.3 | Direct functional replacement: same C INI parsing use-case, comparable API surface and single-file integration pattern. |
| 143 | python-automat | 68.5 | python-statemachine | 79.8 | +11.3 | Provides the same core FSM abstraction and can replace Automat state definitions with only minor API adjustments. |
| 144 | libXinerama | 68.5 | libXrandr | 79.6 | +11.1 | Provides equivalent multi-head geometry information via the modern RandR extension using nearly identical Xlib calling patterns. |
| 145 | apache-ant | 79.4 | Gradle | 90.4 | +11.0 | Direct functional replacement providing equivalent build automation, task execution and dependency management via modern DSL. |
| 146 | distcc | 62.5 | icecream | 73.0 | +10.5 | Direct functional replacement providing the same distributed C/C++ compilation daemon and client usage pattern. |
| 147 | apr | 66.5 | glib | 76.8 | +10.3 | Direct functional replacement providing equivalent OS-portability APIs at the same C abstraction layer. |
| 148 | rubygem-llhttp-ffi | 66.5 | http_parser.rb | 76.8 | +10.3 | Direct drop-in for HTTP message parsing via a similar low-level parser API in Ruby |
| 149 | rubygem-httpclient | 68.5 | rest-client | 78.6 | +10.1 | Provides near-identical synchronous HTTP client usage for common operations without architectural changes. |
| 150 | httpd | 77.4 | Nginx | 87.5 | +10.1 | Direct functional replacement as a standalone HTTP daemon with equivalent request handling and module extensibility. |
| 151 | gnutls | 79.4 | OpenSSL | 89.2 | +9.8 | Direct API-compatible TLS library replacement for the same transport-security use cases in C. |
| 152 | glog | 80.5 | spdlog | 90.1 | +9.6 | Direct drop-in C++ logging replacement with similar macros and sinks; same sync/async usage patterns. |
| 153 | squid | 74.5 | Varnish Cache | 84.0 | +9.5 | Direct functional replacement as an HTTP caching proxy daemon with comparable configuration-driven usage. |
| 154 | json-c | 78.4 | cJSON | 87.7 | +9.3 | Direct C JSON API replacement with similar parse/print functions and object model. |
| 155 | python-cffi | 83.4 | ctypes | 92.6 | +9.2 | Direct stdlib FFI API for loading and calling C functions from Python; same use cases, no external deps. |
| 156 | salt3 | 80.8 | ansible | 89.9 | +9.1 | Direct functional replacement: same Python runtime, CLI/daemon usage pattern, and infrastructure automation abstraction for configuration m… |
| 157 | python-CacheControl | 76.5 | requests-cache | 85.6 | +9.1 | Provides identical requests.Session caching semantics with backend storage options. |
| 158 | python-portalocker | 78.4 | filelock | 87.4 | +9.0 | Direct functional replacement offering identical file-locking semantics via acquire/release or context managers in pure Python. |
| 159 | rubygem-signet | 78.5 | oauth2 | 87.4 | +8.9 | Provides identical OAuth2 client usage pattern for token acquisition and refresh without code restructuring. |
| 160 | rubygem-http-form_data | 76.0 | multipart-post | 84.9 | +8.9 | Direct functional replacement providing identical multipart form-data building API usable by the same Ruby HTTP clients. |
| 161 | tar | 78.5 | bsdtar | 87.4 | +8.9 | Direct CLI tar-compatible archiver that reads/writes the same .tar formats and can replace GNU tar in scripts and build systems with minima… |
| 162 | perl-Module-ScanDeps | 64.5 | Perl::PrereqScanner | 73.2 | +8.7 | Direct functional replacement performing static Perl dependency scanning at same abstraction level. |
| 163 | python-fuse | 70.5 | pyfuse3 | 79.1 | +8.6 | Direct functional replacement providing Python bindings to FUSE at the same abstraction layer with compatible mount and operation patterns. |
| 164 | nginx-ingress | 83.4 | traefik | 92.0 | +8.6 | Same-layer Kubernetes Ingress controller; users can switch via IngressClass without changing routing rules. |
| 165 | python-ruamel-yaml | 78.5 | PyYAML | 87.1 | +8.6 | Direct functional replacement providing equivalent YAML load/dump operations at the same abstraction layer with near-identical usage patter… |
| 166 | calico-confd | 71.5 | consul-template | 80.1 | +8.6 | Direct functional replacement: same CLI/daemon pattern, watches KV store and renders templates to disk without code changes. |
| 167 | libssh | 73.5 | libssh2 | 81.9 | +8.4 | Direct C SSH2 client library with comparable API surface for session, SFTP and channel operations. |
| 168 | mc | 81.4 | nnn | 89.8 | +8.4 | Direct CLI drop-in replacement: same terminal two-pane navigation use-case, C implementation, identical install/run pattern. |
| 169 | python-pyparsing | 80.5 | lark | 88.9 | +8.4 | Direct functional replacement: same Python runtime, grammar-based text parsing at identical abstraction level, sync API, actively maintaine… |
| 170 | apache-maven | 82.8 | Gradle | 90.9 | +8.1 | Direct functional replacement providing equivalent Java build/dependency management with comparable CLI usage and plugin model. |
| 171 | perl-YAML | 63.8 | YAML::XS | 71.9 | +8.1 | Direct API-compatible replacement with same Load/Dump usage pattern. |
| 172 | python-flit-core | 79.5 | hatch | 87.5 | +8.0 | Direct drop-in build backend via hatchling for flit_core users with identical pyproject.toml usage. |
| 173 | sendmail | 65.5 | exim | 73.5 | +8.0 | Same-layer MTA providing equivalent email routing and delivery functionality. |
| 174 | vsftpd | 64.0 | ProFTPD | 71.9 | +7.9 | Serves as a drop-in FTP daemon alternative with matching runtime model and configuration-driven operation. |
| 175 | ecdsa | 82.4 | cryptography | 90.2 | +7.8 | Direct functional replacement providing equivalent ECDSA sign/verify operations on the same curves with nearly identical API patterns. |
| 176 | uwsgi | 69.8 | Waitress | 77.5 | +7.7 | Pure-Python WSGI server usable as direct swap for uWSGI in Python web deployments. |
| 177 | wget | 80.4 | curl | 88.0 | +7.6 | Direct CLI drop-in replacement for non-interactive HTTP/FTP file retrieval with comparable flags and output behavior. |
| 178 | rubygem-highline | 67.5 | cli-ui | 74.8 | +7.3 | Provides comparable interactive CLI prompting and formatting as a drop-in Ruby library |
| 179 | mariadb | 80.4 | MySQL Server | 87.5 | +7.1 | Direct functional replacement; identical client protocol, SQL dialect and replication allow zero-code-change swap for most workloads. |
| 180 | vernemq | 80.5 | emqx | 87.5 | +7.0 | Direct drop-in Erlang MQTT broker with compatible clustering and protocol support for seamless swap |
| 181 | rubygem-http | 80.5 | faraday | 87.4 | +6.9 | Direct functional replacement as a Ruby HTTP client with comparable sync request patterns and minimal code changes for basic use cases. |
| 182 | findutils | 84.0 | fd | 90.9 | +6.9 | Direct CLI replacement for GNU find with equivalent file-search functionality and simpler syntax |
| 183 | python-webob | 78.5 | Werkzeug | 85.4 | +6.9 | Direct WSGI Request/Response replacement at same abstraction layer with compatible API patterns. |
| 184 | python-pam | 67.5 | pamela | 74.4 | +6.9 | Direct functional replacement providing equivalent PAM authentication primitives with nearly identical usage patterns. |
| 185 | gperftools | 82.4 | mimalloc | 89.2 | +6.8 | Direct malloc API replacement usable via LD_PRELOAD or relinking, same C/C++ runtime layer as tcmalloc. |
| 186 | vernemq | 80.5 | mosquitto | 87.2 | +6.7 | Standard MQTT broker providing identical pub/sub semantics and config-driven daemon usage |
| 187 | perl-Config-IniFiles | 64.5 | Config::Tiny | 71.2 | +6.7 | Direct functional replacement for basic INI read/write with nearly identical usage pattern in Perl |
| 188 | rubygem-builder | 77.4 | nokogiri | 83.8 | +6.4 | Nokogiri::XML::Builder offers a compatible DSL for XML generation at the same abstraction level, allowing minimal code changes for most bui… |
| 189 | rubygem-webrick | 70.5 | thin | 76.8 | +6.3 | Lightweight Rack HTTP server that can directly substitute for WEBrick in simple server setups |
| 190 | util-linux | 78.5 | busybox | 84.8 | +6.3 | Provides equivalent CLI utilities as a single static binary, directly substitutable for util-linux commands in scripts and initramfs. |
| 191 | libgcrypt | 76.5 | OpenSSL | 82.8 | +6.3 | Provides equivalent low-level crypto primitives (ciphers, digests, PK, RNG) via libcrypto with comparable C API usage patterns. |
| 192 | duktape | 77.5 | quickjs | 83.8 | +6.3 | Direct drop-in embeddable JS engine with comparable C API and footprint for the same scripting use cases. |
| 193 | apache-ant | 79.4 | Apache Maven | 85.6 | +6.2 | Provides identical build lifecycle and dependency resolution capabilities as a drop-in CLI/Java build tool. |
| 194 | python-fuse | 70.5 | fusepy | 76.6 | +6.1 | Provides equivalent FUSE filesystem implementation in Python with nearly identical usage for basic mount and callback patterns. |
| 195 | grep | 85.5 | ripgrep | 91.5 | +6.0 | Direct CLI grep replacement supporting identical regex search workflows and flags. |
| 196 | gnutls | 79.4 | mbed TLS | 85.4 | +6.0 | Same-layer TLS library providing equivalent secure transport functionality in C. |
| 197 | nspr | 71.5 | APR | 77.4 | +5.9 | Direct functional replacement providing equivalent OS portability layer for threads, sockets and file I/O in C. |
| 198 | perl-JSON | 68.5 | JSON::XS | 74.4 | +5.9 | Direct functional replacement offering identical encode/decode interface with higher performance. |
| 199 | rubygem-mime-types-data | 79.5 | marcel | 85.2 | +5.7 | Provides equivalent MIME type registry and lookup API at same abstraction layer for Ruby apps. |
| 200 | python-ujson | 83.4 | orjson | 88.9 | +5.5 | Direct drop-in for ujson use cases with faster performance and maintained API compatibility for loads/dumps. |
| 201 | perl-Module-Build | 62.5 | Module-Build-Tiny | 68.0 | +5.5 | Direct functional replacement using same Build.PL interface and Perl build workflow. |
| 202 | python-requests-oauthlib | 82.4 | authlib | 87.8 | +5.4 | Authlib supplies equivalent OAuth1/OAuth2 client classes and can be passed directly to requests via auth= parameter for identical usage. |
| 203 | gnutls | 79.4 | wolfSSL | 84.8 | +5.4 | Drop-in TLS replacement via OpenSSL compatibility API for identical C usage patterns. |
| 204 | iptables | 80.5 | nftables | 85.9 | +5.4 | Direct drop-in CLI replacement at same kernel layer for packet filtering/NAT use cases. |
| 205 | gflags | 70.5 | cxxopts | 75.8 | +5.3 | Provides the same core command-line flag parsing capability as a drop-in C++ library replacement. |
| 206 | nss | 66.5 | gnutls | 71.8 | +5.3 | Same-layer TLS/crypto replacement; comparable API for secure connections and PKI. |
| 207 | newt | 71.4 | cdk | 76.6 | +5.2 | Direct C library replacement providing comparable text UI widgets and dialog components with similar integration pattern. |
| 208 | python-mistune | 81.4 | markdown | 86.6 | +5.2 | Direct functional replacement providing equivalent Markdown-to-HTML conversion with comparable extension hooks. |
| 209 | crun | 84.4 | runc | 89.6 | +5.2 | Direct functional replacement implementing identical OCI runtime spec and CLI usage pattern. |
| 210 | cracklib | 67.5 | libpwquality | 72.6 | +5.1 | Direct functional replacement providing the same password-strength checking layer with compatible C API and PAM integration. |
| 211 | libmicrohttpd | 79.5 | civetweb | 84.6 | +5.1 | Direct C embeddable HTTP server drop-in with comparable synchronous API and TLS support. |
| 212 | rubygem-retriable | 82.4 | retryable | 87.4 | +5.0 | Direct drop-in replacement providing identical retry-with-backoff semantics via a compatible Ruby DSL. |
| 213 | nginx-ingress | 83.4 | ingress-nginx | 88.2 | +4.8 | Direct drop-in replacement implementing the same Kubernetes Ingress API with NGINX data plane. |
| 214 | libedit | 78.0 | readline | 82.8 | +4.8 | Direct functional replacement offering the same readline-compatible line-editing API at the C library layer. |
| 215 | flannel | 79.4 | cilium | 83.9 | +4.5 | Direct CNI replacement providing equivalent pod networking via VXLAN/eBPF overlay with same Kubernetes install pattern. |
| 216 | python-dateutil | 85.4 | arrow | 89.9 | +4.5 | Direct functional replacement providing comparable date parsing, manipulation and formatting APIs in pure Python. |
| 217 | libmicrohttpd | 79.5 | mongoose | 84.0 | +4.5 | Provides equivalent embeddable HTTP server functionality in C with similar usage patterns. |
| 218 | python-urllib3 | 85.9 | httpx | 90.3 | +4.4 | Direct functional replacement providing equivalent sync HTTP client with pooling and retries. |
| 219 | geos | 81.4 | Boost.Geometry | 85.6 | +4.2 | Direct C++ drop-in replacement for 2D geometric algorithms and spatial predicates. |
| 220 | rubygem-optimist | 81.4 | slop | 85.4 | +4.0 | Direct functional replacement providing the same CLI option parsing abstraction and usage pattern in Ruby. |
| 221 | snappy | 83.4 | lz4 | 87.4 | +4.0 | Direct functional replacement providing comparable ultra-fast compression/decompression with similar low-level block APIs usable in the sam… |
| 222 | python-pyflakes | 76.5 | pylint | 80.5 | +4.0 | Functional replacement: pylint detects the same undefined names, unused imports and similar issues with comparable CLI invocation. |
| 223 | groff | 72.5 | mandoc | 76.4 | +3.9 | Provides identical man page rendering via same troff-like input without code changes. |
| 224 | jansson | 83.8 | cJSON | 87.7 | +3.9 | Direct C JSON manipulation library with similar encode/decode API usable as drop-in replacement in most C codebases. |
| 225 | python-lxml | 81.0 | xml.etree.ElementTree | 84.8 | +3.8 | Provides nearly identical ElementTree API; lxml is explicitly designed as a drop-in accelerator for the same interface. |
| 226 | http-parser | 61.4 | picohttpparser | 65.2 | +3.8 | Provides equivalent low-level HTTP message parsing functionality in C with comparable sync usage. |
| 227 | rubygem-protocol-http2 | 79.5 | http-2 | 83.2 | +3.7 | Direct drop-in HTTP/2 protocol library in Ruby offering equivalent framing and connection primitives. |
| 228 | paho-c | 83.4 | libmosquitto | 87.1 | +3.7 | Direct C MQTT client library with nearly identical sync publish/subscribe API. |
| 229 | python-oauthlib | 78.5 | authlib | 82.0 | +3.5 | Direct functional replacement providing equivalent OAuth1/OAuth2 client and server abstractions in Python. |
| 230 | make | 82.4 | Ninja | 85.8 | +3.4 | Direct functional replacement as a low-level build executor invoked identically via CLI for the same generated build graphs. |
| 231 | json-c | 78.4 | Jansson | 81.8 | +3.4 | Provides equivalent C JSON object manipulation and I/O APIs. |
| 232 | make | 82.4 | Meson | 85.7 | +3.3 | Provides equivalent CLI-driven build automation for the same native project use cases. |
| 233 | htop | 84.4 | btop | 87.7 | +3.3 | Direct CLI drop-in interactive process and resource monitor with comparable keyboard navigation and real-time display. |
| 234 | python-flit-core | 79.5 | poetry | 82.7 | +3.2 | Functional replacement for packaging and publishing workflows with comparable CLI and pyproject.toml support. |
| 235 | mkinitcpio | 78.5 | dracut | 81.7 | +3.2 | Direct CLI drop-in replacement for generating initramfs images with comparable hook/modular architecture. |
| 236 | haproxy | 81.4 | Nginx | 84.5 | +3.1 | Nginx provides identical daemon-style reverse-proxy and TCP/HTTP load-balancing use cases with comparable configuration-driven deployment. |
| 237 | netcat | 83.5 | ncat | 86.6 | +3.1 | Direct CLI drop-in replacement for nc TCP/UDP use cases with added features. |
| 238 | toybox | 76.5 | busybox | 79.4 | +2.9 | Provides identical CLI utilities in a single binary; same C implementation and usage pattern. |
| 239 | zsh | 85.4 | fish | 88.2 | +2.8 | Direct interactive shell replacement with comparable CLI usage pattern and active distribution. |
| 240 | backward-cpp | 79.5 | boost-stacktrace | 82.3 | +2.8 | Provides equivalent stack-trace functionality at the same abstraction level and can be used as a drop-in in C++ codebases already using Boo… |
| 241 | rubygem-mini_mime | 81.4 | marcel | 84.2 | +2.8 | Provides equivalent MIME type lookup and extension mapping with nearly identical usage patterns for Ruby applications. |
| 242 | python-chardet | 78.5 | charset-normalizer | 81.2 | +2.7 | Actively maintained drop-in replacement with identical detect() usage pattern and superior Unicode handling. |
| 243 | XML-Parser | 66.5 | XML-LibXML | 69.2 | +2.7 | Direct functional replacement providing similar SAX/DOM parsing with better performance and maintained API compatibility for existing Perl … |
| 244 | calico | 83.5 | cilium | 86.2 | +2.7 | Direct CNI/network-policy replacement at same abstraction layer with comparable daemon-based deployment. |
| 245 | perl-JSON | 68.5 | Cpanel::JSON::XS | 71.2 | +2.7 | Actively maintained drop-in replacement with extended functionality and same usage patterns. |
| 246 | socat | 81.5 | ncat | 84.2 | +2.7 | Direct CLI drop-in replacement providing equivalent socket relay, listen, and exec functionality |
| 247 | nano | 83.5 | micro | 86.0 | +2.5 | Direct CLI drop-in replacement providing the same simple editing workflow with improved defaults and no learning curve for basic nano users. |
| 248 | ddclient | 79.5 | inadyn | 82.0 | +2.5 | Direct CLI/daemon DDNS updater with overlapping provider support and comparable usage pattern. |
| 249 | grub2 | 80.5 | systemd-boot | 82.9 | +2.4 | Direct UEFI bootloader replacement for GRUB in modern Linux setups with comparable kernel loading and EFI variable handling. |
| 250 | bindutils | 76.4 | knot-dns | 78.7 | +2.3 | Direct authoritative DNS server replacement; same daemon model, zone-file compatible, comparable CLI tooling. |
| 251 | nettle | 76.5 | libgcrypt | 78.8 | +2.3 | Direct functional replacement providing the same low-level crypto primitives with comparable C API usage patterns. |
| 252 | graphene | 82.5 | strawberry-graphql | 84.8 | +2.3 | Direct functional replacement providing equivalent GraphQL schema building in Python with minimal code changes for type-based definitions. |
| 253 | backward-cpp | 79.5 | cpptrace | 81.7 | +2.2 | Direct functional replacement providing similar stack-trace capture and pretty-print APIs for C++ crash handling. |
| 254 | jemalloc | 85.5 | mimalloc | 87.7 | +2.2 | Direct drop-in C memory allocator; same LD_PRELOAD usage pattern and API compatibility for malloc/free. |
| 255 | perl-JSON-XS | 79.5 | JSON::PP | 81.6 | +2.1 | Same JSON problem and identical high-level API usable as drop-in without XS dependency. |
| 256 | passwdqc | 72.5 | libpwquality | 74.6 | +2.1 | Provides equivalent C library and PAM module for password strength enforcement with similar API usage. |
| 257 | nmap | 87.8 | masscan | 89.8 | +2.0 | Direct CLI port-scanner replacement with comparable command-line usage pattern and output formats. |
| 258 | dbus | 80.5 | sd-bus | 82.5 | +2.0 | Provides equivalent D-Bus IPC messaging at the same C library layer with compatible protocol support. |
| 259 | syslog-ng | 74.8 | rsyslog | 76.8 | +2.0 | Direct functional replacement as a syslog daemon; same CLI/daemon usage pattern, protocol compatibility, and configuration layer allowing s… |
| 260 | influxdb | 85.4 | VictoriaMetrics | 87.3 | +1.9 | Direct functional replacement via full InfluxDB line protocol, write and query API compatibility for identical client usage. |
| 261 | rubygem-representable | 78.4 | blueprinter | 80.2 | +1.8 | Provides equivalent declarative object-to-JSON mapping with similar usage pattern and minimal code changes. |
| 262 | gcc | 89.8 | clang | 91.6 | +1.8 | Direct C/C++ compiler replacement; same CLI flags and language support allow swapping via CC variable with minimal changes. |
| 263 | python-hatchling | 87.4 | setuptools | 89.2 | +1.8 | Standard PEP 517 build backend that replaces hatchling in pyproject.toml with no architecture changes. |
| 264 | rubygem-http | 80.5 | rest-client | 82.2 | +1.7 | Serves as a drop-in Ruby HTTP client alternative with matching synchronous API for common request operations. |
| 265 | mc | 81.4 | vifm | 83.1 | +1.7 | Same abstraction layer CLI file manager; C codebase, two-pane orthodox UI, direct swap for navigation tasks. |
| 266 | python3-pyelftools | 81.4 | LIEF | 83.0 | +1.6 | Provides Python API for direct ELF parsing and inspection, usable as functional replacement for most pyelftools read-only workflows. |
| 267 | mozjs | 81.1 | Chromium | 82.6 | +1.5 | Direct functional replacement as a standards-compliant web browser with identical usage for end-users and web content. |
| 268 | vim | 88.7 | neovim | 90.1 | +1.4 | Direct functional replacement: same modal editing model, CLI invocation and configuration migration path with no code changes required for … |
| 269 | lldb | 84.3 | gdb | 85.6 | +1.3 | Direct CLI debugger replacement supporting identical languages and targets with compatible command interface. |
| 270 | libgcrypt | 76.5 | mbed TLS | 77.8 | +1.3 | Supplies the same cryptographic building blocks (symmetric, hash, PK, RNG) in C with direct function-call usage matching libgcrypt patterns. |
| 271 | cppcheck | 86.8 | clang-tidy | 88.0 | +1.2 | Direct CLI static analyzer for same C/C++ bug detection use cases |
| 272 | openjdk | 83.5 | Amazon Corretto | 84.7 | +1.2 | Binary-compatible OpenJDK build offering identical runtime semantics and tooling. |
| 273 | perl-YAML | 63.8 | YAML::PP | 65.0 | +1.2 | Drop-in functional replacement using identical high-level API. |
| 274 | openjdk | 83.5 | Eclipse Temurin | 84.6 | +1.1 | TCK-certified OpenJDK distribution providing identical JVM behavior and command-line interface. |
| 275 | python-dateutil | 85.4 | pendulum | 86.5 | +1.1 | Provides equivalent high-level datetime operations and parsing with modern timezone handling. |
| 276 | flannel | 79.4 | calico | 80.4 | +1.0 | Same-layer CNI overlay/network-policy solution installed identically to Flannel for Kubernetes clusters. |
| 277 | rsyslog | 78.4 | syslog-ng | 79.3 | +0.9 | Direct functional replacement as a syslog daemon with comparable configuration, performance, and output modules. |
| 278 | python-Js2Py | 68.5 | quickjs | 69.4 | +0.9 | Direct functional replacement providing a Python-callable JS runtime at the same abstraction level for executing/translating JS code. |
| 279 | python-prettytable | 83.5 | tabulate | 84.4 | +0.9 | Direct functional replacement providing identical table formatting output via a simple function call. |
| 280 | mysql | 81.5 | mariadb | 82.4 | +0.9 | Direct protocol and SQL-level drop-in replacement allowing existing MySQL client code and drivers to connect unchanged. |
| 281 | geos | 81.4 | CGAL | 82.3 | +0.9 | Provides equivalent 2D/3D geometric operations and predicates as a C++ library. |
| 282 | rubygem-terminal-table | 80.5 | tty-table | 81.2 | +0.7 | Direct drop-in replacement providing identical terminal table output with comparable or improved customization options. |
| 283 | gperftools | 82.4 | jemalloc | 83.0 | +0.6 | Direct API-compatible malloc replacement via LD_PRELOAD or relinking for identical C/C++ use cases. |
| 284 | rubygem-rest-client | 76.5 | excon | 77.1 | +0.6 | Lightweight Ruby HTTP client usable as functional replacement for simple REST calls. |
| 285 | gzip | 87.5 | pigz | 88.1 | +0.6 | Direct CLI-compatible gzip replacement using same DEFLATE format and flags. |
| 286 | python-deepmerge | 80.8 | mergedeep | 81.3 | +0.5 | Provides identical deep-merge API for dicts; drop-in import and call replacement. |
| 287 | kube-bench | 86.8 | kubescape | 87.2 | +0.4 | Direct functional replacement: same CIS benchmark checks via CLI, identical usage pattern and output formats. |
| 288 | perl-libwww-perl | 83.4 | HTTP::Tiny | 83.8 | +0.4 | Direct drop-in Perl HTTP client for the same sync request use cases as LWP::UserAgent. |
| 289 | rubygem-net-http | 87.0 | faraday | 87.3 | +0.3 | Functional HTTP client drop-in via net-http adapter preserving sync patterns for existing Ruby codebases. |
| 290 | tcpdump | 85.4 | tshark | 85.7 | +0.3 | Direct CLI drop-in replacement for packet capture/display/filtering use cases with comparable command-line interface. |
| 291 | lshw | 71.5 | hwinfo | 71.8 | +0.3 | Provides comparable low-level hardware listing via CLI for the same Linux hardware reporting scenarios. |
| 292 | python-attrs | 87.1 | dataclasses | 87.4 | +0.3 | Direct functional replacement via @dataclass decorator providing equivalent attribute definition and generation without external dependency. |
| 293 | bash | 87.4 | zsh | 87.7 | +0.3 | Direct CLI shell replacement supporting nearly all bash syntax and scripts with minimal changes. |
| 294 | wpa_supplicant | 82.8 | iwd | 83.0 | +0.2 | Direct functional replacement at the same daemon/CLI layer for Wi-Fi authentication on Linux, usable without code changes in most setups. |
| 295 | bubblewrap | 82.5 | firejail | 82.6 | +0.1 | Direct CLI sandbox replacement using similar Linux kernel features for process isolation. |
| 296 | ibmtpm | 79.5 | swtpm | 79.6 | +0.1 | Provides equivalent TPM 2.0 socket server functionality; users can point existing test harnesses at swtpm with minimal flag changes. |

