# Package Classifier — Branch master

_Generated: 2026-05-10T21:34:00+00:00_  
_Records considered (this branch): 603; deduplicated: 10 of top 10_  

### 1. Python — composite_score 93.1
[https://www.python.org/](https://www.python.org/)  
**Resume:** Core Python programming language distribution (interpreter and standard library).

### 2. coreutils — composite_score 92.8
[https://www.gnu.org/software/coreutils/](https://www.gnu.org/software/coreutils/)  
**Resume:** GNU collection of basic file, shell and text manipulation utilities (ls, cp, cat, etc.).

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | uutils-coreutils | 89.4 | Direct functional CLI replacement providing the same utilities with compatible command-line behavior. |

### 3. nokogiri — composite_score 92.5
[https://nokogiri.org/](https://nokogiri.org/)  
**Resume:** Nokogiri is an HTML, XML, SAX, and Reader parser with XPath and CSS selector support.

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | ox | 84.8 | Direct drop-in XML/HTML parser replacement for Nokogiri use cases with comparable Ruby APIs. |
| 2 | oga | 81.2 | Pure-Ruby XML/HTML parser that can replace Nokogiri for parsing and querying without native deps. |

### 4. curl — composite_score 92.2
[https://curl.se/](https://curl.se/)  
**Resume:** Command-line tool and C library for transferring data with URLs

### 5. networkx — composite_score 91.8
[https://networkx.org/](https://networkx.org/)  
**Resume:** Python library for creating, manipulating, and studying complex networks/graphs.

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | igraph | 83.2 | Direct Python graph library with comparable Graph object and algorithm coverage; minimal code changes for core use cases. |
| 2 | graph-tool | 73.0 | Python graph analysis library offering overlapping network algorithms and data structures for direct substitution. |

### 6. PostgreSQL — composite_score 90.8
[https://www.postgresql.org/](https://www.postgresql.org/)  
**Resume:** Open-source object-relational database management system.

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | MariaDB | 88.5 | Direct drop-in RDBMS replacement with MySQL-compatible interface for minimal migration effort. |
| 2 | MySQL | 86.8 | Direct drop-in RDBMS replacement supporting equivalent SQL workloads and client drivers. |

### 7. activesupport — composite_score 90.1
[https://github.com/rails/rails/tree/main/activesupport](https://github.com/rails/rails/tree/main/activesupport)  
**Resume:** Toolkit of support libraries and Ruby core extensions extracted from Rails

### 8. aws-sdk-kms — composite_score 89.4
[https://rubygems.org/gems/aws-sdk-kms](https://rubygems.org/gems/aws-sdk-kms)  
**Resume:** Official AWS SDK for Ruby client for Amazon Key Management Service (KMS).

### 9. bundler — composite_score 89.1
[https://bundler.io](https://bundler.io)  
**Resume:** Manages Ruby application dependencies via Gemfile across machines, systematically and repeatably.

### 10. sudo — composite_score 89.0
[https://www.sudo.ws/sudo/](https://www.sudo.ws/sudo/)  
**Resume:** Allows permitted users to execute commands as the superuser or another user as specified by a security policy.

**Top alternatives:**

| # | Name | Composite | Rationale |
|---|---|---|---|
| 1 | doas | 82.5 | Direct CLI replacement providing equivalent privilege escalation with simpler policy syntax. |

## Alternatives outscoring the package

_114 alternative(s) score higher than the corresponding package._

| # | Package | Pkg score | Alternative | Alt score | Δ | Rationale |
|---|---|---|---|---|---|---|
| 1 | Apache Commons HttpClient | 35.5 | OkHttp | 89.0 | +53.5 | Widely adopted modern HTTP client usable as direct replacement for classic sync calls. |
| 2 | Apache Commons HttpClient | 35.5 | Apache HttpComponents Client | 86.2 | +50.7 | Official successor maintaining similar request/response API and configuration model. |
| 3 | ipaddr | 45.5 | ipaddress | 89.9 | +44.4 | Direct stdlib successor with equivalent IP parsing/validation primitives |
| 4 | hpricot | 45.5 | nokogiri | 88.1 | +42.6 | Nokogiri provides the same HTML parsing and traversal capabilities with near-identical usage patterns and is the standard replacement for h… |
| 5 | zip | 41.0 | rubyzip | 82.8 | +41.8 | Provides near-identical Zip::ZipFile and entry handling APIs as a modern, maintained drop-in for the legacy zip gem. |
| 6 | mingetty | 41.5 | agetty | 83.2 | +41.7 | agetty provides identical console login prompt functionality and is the standard replacement shipped in util-linux, requiring only config p… |
| 7 | CppUnit | 51.5 | GoogleTest | 92.2 | +40.7 | Direct drop-in C++ unit testing replacement with similar test macros and runner. |
| 8 | lockfile | 49.5 | filelock | 90.0 | +40.5 | Direct drop-in replacement with compatible lock acquisition API and same file-based locking semantics. |
| 9 | tclap | 47.9 | CLI11 | 88.4 | +40.5 | Direct drop-in CLI parser for C++ with similar header-only usage and option handling |
| 10 | nicstat | 42.5 | vnstat | 79.6 | +37.1 | Direct CLI replacement providing equivalent per-NIC byte/packet/error counters with optional persistence. |
| 11 | CppUnit | 51.5 | Catch2 | 88.4 | +36.9 | Functional C++ unit testing replacement supporting same test discovery and assertions. |
| 12 | tclap | 47.9 | cxxopts | 81.9 | +34.0 | Direct functional replacement providing comparable option parsing API in C++ |
| 13 | ebtables | 54.5 | nft | 87.2 | +32.7 | nft bridge family is the direct in-kernel successor providing identical frame-filtering capabilities via a unified CLI. |
| 14 | Info-ZIP Zip | 51.5 | 7-Zip | 84.0 | +32.5 | Direct CLI replacement for ZIP archive creation/extraction using identical file format and comparable command-line flags. |
| 15 | ivykis | 54.0 | libevent | 86.1 | +32.1 | Provides comparable event multiplexing abstraction and can replace ivykis usage patterns with minimal API adaptation in C codebases. |
| 16 | lockfile | 49.5 | fasteners | 81.0 | +31.5 | Provides equivalent inter-process file locking via InterProcessLock with minimal API changes. |
| 17 | thread_safe | 58.5 | concurrent-ruby | 89.1 | +30.6 | Provides the same thread-safe maps, sets and atomic classes with compatible APIs; actively maintained successor. |
| 18 | libxml-ruby | 57.5 | nokogiri | 87.0 | +29.5 | Direct functional replacement providing equivalent XML parsing and XPath APIs in Ruby with broader adoption and easier installation. |
| 19 | ipaddr | 45.5 | netaddr | 74.6 | +29.1 | Actively maintained Python library providing comparable IP address handling |
| 20 | unzip | 53.5 | 7-Zip | 82.5 | +29.0 | Provides identical CLI usage pattern for ZIP extraction as a drop-in command replacement. |
| 21 | atftp | 47.5 | tftp-hpa | 75.8 | +28.3 | Direct drop-in TFTP daemon/client replacement with identical UDP CLI usage and PXE features. |
| 22 | CppUnit | 51.5 | Boost.Test | 79.1 | +27.6 | Direct C++ unit testing library replacement with comparable test suite execution. |
| 23 | cdrkit | 52.0 | xorriso | 79.0 | +27.0 | Provides equivalent ISO creation and optical drive burning via xorriso command-line interface usable as drop-in for cdrkit tools. |
| 24 | mlocate | 55.5 | plocate | 81.2 | +25.7 | Direct CLI-compatible replacement using the same locate/updatedb interface and database model. |
| 25 | Photon | 62.5 | Alpine Linux | 88.0 | +25.5 | Direct functional replacement as minimal container OS; same layer, usage pattern via container images. |
| 26 | libev | 61.5 | libuv | 86.1 | +24.6 | Direct drop-in replacement providing equivalent event-loop primitives (timers, I/O watchers, async) with a comparable C API. |
| 27 | trollop | 58.5 | slop | 83.0 | +24.5 | Direct drop-in replacement providing nearly identical option parsing DSL and usage for CLI scripts. |
| 28 | nicstat | 42.5 | nload | 66.2 | +23.7 | Provides the same live per-interface throughput view via a simple terminal CLI. |
| 29 | dejavu-fonts-ttf | 55.5 | liberation-fonts | 78.8 | +23.3 | Provides drop-in TTF fonts with similar Unicode coverage and usage pattern for desktop/document rendering. |
| 30 | multi_json | 62.5 | oj | 85.6 | +23.1 | Direct functional replacement providing identical JSON load/dump API with superior performance; users can swap via require 'oj' and Oj.mimi… |
| 31 | traceroute | 62.8 | mtr | 85.7 | +22.9 | mtr directly replaces traceroute for route tracing with enhanced real-time display and identical CLI usage pattern. |
| 32 | LZO | 68.5 | LZ4 | 91.4 | +22.9 | Direct drop-in for LZO's fast compression use-cases with nearly identical C function signatures and block/stream APIs. |
| 33 | Photon | 62.5 | Bottlerocket | 83.8 | +21.3 | Direct container-host OS replacement with comparable minimal footprint and update model. |
| 34 | recursive-open-struct | 67.5 | hashie | 88.4 | +20.9 | Hashie::Mash is a direct functional replacement offering the same recursive dot-notation access pattern on nested hashes. |
| 35 | sendmail | 65.5 | postfix | 86.2 | +20.7 | Direct functional MTA replacement using same SMTP protocol and daemon model; widely adopted as Sendmail successor. |
| 36 | libxml-ruby | 57.5 | ox | 78.1 | +20.6 | Drop-in Ruby XML parsing library with similar low-level node access patterns and no external libxml dependency. |
| 37 | cscope | 55.5 | GNU Global | 75.8 | +20.3 | Provides identical symbol cross-referencing and source navigation via CLI and cscope-compatible interface. |
| 38 | highline | 67.5 | tty-prompt | 87.2 | +19.7 | Direct functional replacement providing equivalent interactive CLI prompting and menu APIs in Ruby |
| 39 | libev | 61.5 | libevent | 81.2 | +19.7 | Provides the same core event-loop abstraction (event_base, watchers) and can replace libev usage patterns with minimal code changes. |
| 40 | ivykis | 54.0 | libev | 73.2 | +19.2 | Direct functional peer for async I/O multiplexing in C; same abstraction level and usage pattern for event handling. |
| 41 | domain_name | 71.4 | public_suffix | 89.8 | +18.4 | Direct functional replacement providing identical Public Suffix List domain parsing and validation in Ruby. |
| 42 | isc-dhcp | 64.5 | kea | 82.6 | +18.1 | Official ISC replacement offering identical DHCP server functionality with improved architecture and active maintenance. |
| 43 | File-Remove | 70.5 | Path-Tiny | 88.2 | +17.7 | Provides direct remove() and recursive directory deletion methods matching File::Remove usage patterns in Perl. |
| 44 | httpclient | 68.5 | faraday | 85.8 | +17.3 | Direct functional replacement providing equivalent HTTP request/response handling with comparable synchronous API patterns. |
| 45 | byacc | 68.5 | bison | 85.8 | +17.3 | Direct functional replacement providing identical yacc-compatible parser generation CLI and input syntax for C users. |
| 46 | runit | 68.5 | s6 | 85.5 | +17.0 | Provides identical service supervision, logging and init functionality with compatible usage patterns and active maintenance. |
| 47 | webrick | 70.5 | puma | 87.4 | +16.9 | Direct Rack-compatible HTTP server replacement usable in the same embedded/testing scenarios as WEBrick |
| 48 | xml-security-c | 64.0 | xmlsec | 80.9 | +16.9 | Direct C/C++ drop-in replacement providing identical XML DSig/Enc APIs and crypto provider abstraction. |
| 49 | virt-what | 71.5 | systemd-detect-virt | 88.2 | +16.7 | Direct CLI drop-in replacement providing identical VM/container detection output. |
| 50 | vsftpd | 64.0 | Pure-FTPd | 80.4 | +16.4 | Direct functional replacement as a standalone secure FTP daemon with comparable CLI/daemon invocation and configuration style. |
| 51 | LZO | 68.5 | Snappy | 84.5 | +16.0 | Provides comparable speed-focused compression/decompression suitable for replacing LZO in performance-critical paths. |
| 52 | nss | 66.5 | openssl | 82.0 | +15.5 | Direct drop-in TLS/crypto provider; same C ABI layer, same use cases (HTTPS, cert validation). |
| 53 | tdb | 67.5 | lmdb | 82.7 | +15.2 | Direct embedded KV replacement with similar C API and file-based storage model. |
| 54 | multi_json | 62.5 | json | 77.0 | +14.5 | Provides the same JSON.parse/JSON.generate interface; multi_json users can replace by requiring 'json' directly. |
| 55 | ntpsec | 74.5 | chrony | 88.6 | +14.1 | Direct drop-in NTP daemon replacement with compatible configuration syntax and command-line tools for time synchronization. |
| 56 | othercertdata.txt | 76.0 | certdata.txt (Mozilla) | 89.5 | +13.5 | Same layer (raw CA list), identical text format and usage pattern as othercertdata.txt; actively maintained by Mozilla. |
| 57 | rdiscount | 77.5 | redcarpet | 90.8 | +13.3 | Direct drop-in Markdown renderer with compatible render API and high performance. |
| 58 | cool.io | 67.5 | eventmachine | 80.5 | +13.0 | Provides comparable event reactor for Ruby network I/O programs with minimal code changes for basic usage patterns |
| 59 | gdbm | 70.5 | lmdb | 83.0 | +12.5 | Direct functional replacement providing comparable embedded key-value storage with similar C API usage patterns. |
| 60 | rest-client | 76.5 | faraday | 88.4 | +11.9 | Direct drop-in Ruby HTTP client replacement with comparable request syntax and adapter flexibility. |
| 61 | yajl-ruby | 78.5 | oj | 90.1 | +11.6 | Direct functional replacement providing identical JSON parse/generate calls with superior performance and maintained compatibility layer |
| 62 | sendmail | 65.5 | exim | 76.0 | +10.5 | Same-layer MTA daemon providing equivalent email routing and delivery functions without code changes for basic use. |
| 63 | llhttp-ffi | 66.5 | http_parser.rb | 76.8 | +10.3 | Direct drop-in for HTTP message parsing via a similar low-level parser API in Ruby |
| 64 | httpclient | 68.5 | rest-client | 78.6 | +10.1 | Provides near-identical synchronous HTTP client usage for common operations without architectural changes. |
| 65 | Squid | 74.5 | Varnish Cache | 84.0 | +9.5 | Direct functional replacement as an HTTP caching proxy daemon with comparable configuration-driven usage. |
| 66 | json-c | 78.4 | cJSON | 87.7 | +9.3 | Direct C JSON API replacement with similar parse/print functions and object model. |
| 67 | http-form_data | 76.0 | multipart-post | 84.9 | +8.9 | Direct functional replacement providing identical multipart form-data building API usable by the same Ruby HTTP clients. |
| 68 | signet | 78.5 | oauth2 | 87.4 | +8.9 | Provides identical OAuth2 client usage pattern for token acquisition and refresh without code restructuring. |
| 69 | tar | 78.5 | bsdtar | 87.4 | +8.9 | Direct CLI tar-compatible archiver that reads/writes the same .tar formats and can replace GNU tar in scripts and build systems with minima… |
| 70 | ruamel.yaml | 78.5 | PyYAML | 87.1 | +8.6 | Direct functional replacement providing equivalent YAML load/dump operations at the same abstraction layer with near-identical usage patter… |
| 71 | vsftpd | 64.0 | ProFTPD | 71.9 | +7.9 | Serves as a drop-in FTP daemon alternative with matching runtime model and configuration-driven operation. |
| 72 | wget | 80.4 | curl | 88.0 | +7.6 | Direct CLI drop-in replacement for non-interactive HTTP/FTP file retrieval with comparable flags and output behavior. |
| 73 | highline | 67.5 | cli-ui | 74.8 | +7.3 | Provides comparable interactive CLI prompting and formatting as a drop-in Ruby library |
| 74 | http | 80.5 | faraday | 87.4 | +6.9 | Direct functional replacement as a Ruby HTTP client with comparable sync request patterns and minimal code changes for basic use cases. |
| 75 | sendmail | 65.5 | opensmtpd | 72.2 | +6.7 | Direct MTA daemon alternative supporting identical core email transfer use cases. |
| 76 | builder | 77.4 | nokogiri | 83.8 | +6.4 | Nokogiri::XML::Builder offers a compatible DSL for XML generation at the same abstraction level, allowing minimal code changes for most bui… |
| 77 | webrick | 70.5 | thin | 76.8 | +6.3 | Lightweight Rack HTTP server that can directly substitute for WEBrick in simple server setups |
| 78 | libgcrypt | 76.5 | OpenSSL | 82.8 | +6.3 | Provides equivalent low-level crypto primitives (ciphers, digests, PK, RNG) via libcrypto with comparable C API usage patterns. |
| 79 | grep | 85.5 | ripgrep | 91.5 | +6.0 | Direct CLI grep replacement supporting identical regex search workflows and flags. |
| 80 | NSPR | 71.5 | APR | 77.4 | +5.9 | Direct functional replacement providing equivalent OS portability layer for threads, sockets and file I/O in C. |
| 81 | mime-types-data | 79.5 | marcel | 85.2 | +5.7 | Provides equivalent MIME type registry and lookup API at same abstraction layer for Ruby apps. |
| 82 | iptables | 80.5 | nftables | 85.9 | +5.4 | Direct drop-in CLI replacement at same kernel layer for packet filtering/NAT use cases. |
| 83 | nss | 66.5 | gnutls | 71.8 | +5.3 | Same-layer TLS/crypto replacement; comparable API for secure connections and PKI. |
| 84 | libmicrohttpd | 79.5 | civetweb | 84.6 | +5.1 | Direct C embeddable HTTP server drop-in with comparable synchronous API and TLS support. |
| 85 | retriable | 82.4 | retryable | 87.4 | +5.0 | Direct drop-in replacement providing identical retry-with-backoff semantics via a compatible Ruby DSL. |
| 86 | libedit | 78.0 | readline | 82.8 | +4.8 | Direct functional replacement offering the same readline-compatible line-editing API at the C library layer. |
| 87 | libmicrohttpd | 79.5 | mongoose | 84.0 | +4.5 | Provides equivalent embeddable HTTP server functionality in C with similar usage patterns. |
| 88 | optimist | 81.4 | slop | 85.4 | +4.0 | Direct functional replacement providing the same CLI option parsing abstraction and usage pattern in Ruby. |
| 89 | groff | 72.5 | mandoc | 76.4 | +3.9 | Provides identical man page rendering via same troff-like input without code changes. |
| 90 | protocol-http2 | 79.5 | http-2 | 83.2 | +3.7 | Direct drop-in HTTP/2 protocol library in Ruby offering equivalent framing and connection primitives. |
| 91 | paho.mqtt.c | 83.4 | libmosquitto | 87.1 | +3.7 | Direct C MQTT client library with nearly identical sync publish/subscribe API. |
| 92 | GNU Make | 82.4 | Ninja | 85.8 | +3.4 | Direct functional replacement as a low-level build executor invoked identically via CLI for the same generated build graphs. |
| 93 | json-c | 78.4 | Jansson | 81.8 | +3.4 | Provides equivalent C JSON object manipulation and I/O APIs. |
| 94 | GNU Make | 82.4 | Meson | 85.7 | +3.3 | Provides equivalent CLI-driven build automation for the same native project use cases. |
| 95 | nc | 83.5 | ncat | 86.6 | +3.1 | Direct CLI drop-in replacement for nc TCP/UDP use cases with added features. |
| 96 | mini_mime | 81.4 | marcel | 84.2 | +2.8 | Provides equivalent MIME type lookup and extension mapping with nearly identical usage patterns for Ruby applications. |
| 97 | socat | 81.5 | ncat | 84.2 | +2.7 | Direct CLI drop-in replacement providing equivalent socket relay, listen, and exec functionality |
| 98 | GRUB | 80.5 | systemd-boot | 82.9 | +2.4 | Direct UEFI bootloader replacement for GRUB in modern Linux setups with comparable kernel loading and EFI variable handling. |
| 99 | nettle | 76.5 | libgcrypt | 78.8 | +2.3 | Direct functional replacement providing the same low-level crypto primitives with comparable C API usage patterns. |
| 100 | JSON::XS | 79.5 | JSON::PP | 81.6 | +2.1 | Same JSON problem and identical high-level API usable as drop-in without XS dependency. |
| 101 | representable | 78.4 | blueprinter | 80.2 | +1.8 | Provides equivalent declarative object-to-JSON mapping with similar usage pattern and minimal code changes. |
| 102 | http | 80.5 | rest-client | 82.2 | +1.7 | Serves as a drop-in Ruby HTTP client alternative with matching synchronous API for common request operations. |
| 103 | pyelftools | 81.4 | LIEF | 83.0 | +1.6 | Provides Python API for direct ELF parsing and inspection, usable as functional replacement for most pyelftools read-only workflows. |
| 104 | Firefox | 81.1 | Chromium | 82.6 | +1.5 | Direct functional replacement as a standards-compliant web browser with identical usage for end-users and web content. |
| 105 | libgcrypt | 76.5 | mbed TLS | 77.8 | +1.3 | Supplies the same cryptographic building blocks (symmetric, hash, PK, RNG) in C with direct function-call usage matching libgcrypt patterns. |
| 106 | Js2Py | 68.5 | quickjs | 69.4 | +0.9 | Direct functional replacement providing a Python-callable JS runtime at the same abstraction level for executing/translating JS code. |
| 107 | terminal-table | 80.5 | tty-table | 81.2 | +0.7 | Direct drop-in replacement providing identical terminal table output with comparable or improved customization options. |
| 108 | gzip | 87.5 | pigz | 88.1 | +0.6 | Direct CLI-compatible gzip replacement using same DEFLATE format and flags. |
| 109 | rest-client | 76.5 | excon | 77.1 | +0.6 | Lightweight Ruby HTTP client usable as functional replacement for simple REST calls. |
| 110 | libwww-perl | 83.4 | HTTP::Tiny | 83.8 | +0.4 | Direct drop-in Perl HTTP client for the same sync request use cases as LWP::UserAgent. |
| 111 | bash | 87.4 | zsh | 87.7 | +0.3 | Direct CLI shell replacement supporting nearly all bash syntax and scripts with minimal changes. |
| 112 | tcpdump | 85.4 | tshark | 85.7 | +0.3 | Direct CLI drop-in replacement for packet capture/display/filtering use cases with comparable command-line interface. |
| 113 | net-http | 87.0 | faraday | 87.3 | +0.3 | Functional HTTP client drop-in via net-http adapter preserving sync patterns for existing Ruby codebases. |
| 114 | wpa_supplicant | 82.8 | iwd | 83.0 | +0.2 | Direct functional replacement at the same daemon/CLI layer for Wi-Fi authentication on Linux, usable without code changes in most setups. |

