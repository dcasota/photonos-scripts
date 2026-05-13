# Snyk Issues Report (5.0)

Generated: 05/13/2026 04:42:32
Total source packages processed: 691
Tool used: SnykCLI

## Summary

| Metric | Count |
|---|---|
| Total issues overall | 58295 |
| High with crypto | 230 |
| High without crypto | 635 |
| Medium | 21849 |
| Low | 35581 |

## Top 10 High Categories

| Category | Count |
| --- | --- |
| Use of a Broken or Risky Cryptographic Algorithm | 193 |
| Hardcoded Secret | 131 |
| Potential Negative Number Used as Index | 120 |
| Path Traversal | 68 |
| Command Injection | 65 |
| Generation of Error Message Containing Sensitive Information | 38 |
| Cross-site Scripting (XSS) | 37 |
| Size Used as Index | 36 |
| Hardcoded Non-Cryptographic Secret | 33 |
| XML External Entity (XXE) Injection | 29 |


### Top 10 Packages with HIGH issues in category "Use of a Broken or Risky Cryptographic Algorithm" (category total=193)

| Package | Count |
| --- | --- |
| jdk21u | 54 |
| jdk11u | 54 |
| jdk17u | 53 |
| runtime | 19 |
| pycryptodome | 3 |
| podman | 2 |
| common | 2 |
| apr-util | 2 |
| apr | 2 |
| mysql-server | 1 |

### Top 10 Packages with HIGH issues in category "Hardcoded Secret" (category total=131)

| Package | Count |
| --- | --- |
| jdk11u | 44 |
| jdk21u | 43 |
| jdk17u | 42 |
| runtime | 1 |
| kafka | 1 |

### Top 10 Packages with HIGH issues in category "Potential Negative Number Used as Index" (category total=120)

| Package | Count |
| --- | --- |
| llvm-project | 35 |
| wireshark | 6 |
| redis | 6 |
| server | 5 |
| mysql-server | 5 |
| node | 4 |
| nvme-cli | 3 |
| ntp | 3 |
| libxcrypt | 3 |
| systemtap | 2 |

### Top 10 Packages with HIGH issues in category "Path Traversal" (category total=68)

| Package | Count |
| --- | --- |
| ruby | 18 |
| podman | 8 |
| govmomi | 7 |
| telegraf | 6 |
| zookeeper | 4 |
| runtime | 3 |
| go | 3 |
| common | 3 |
| src | 2 |
| moby | 2 |

### Top 10 Packages with HIGH issues in category "Command Injection" (category total=65)

| Package | Count |
| --- | --- |
| go | 19 |
| podman | 8 |
| common | 7 |
| termshark | 4 |
| etcd | 4 |
| containerd | 4 |
| moby | 3 |
| libcap | 3 |
| heapster | 2 |
| guest-agent | 2 |

### Top 10 Packages with HIGH issues in category "Generation of Error Message Containing Sensitive Information" (category total=38)

| Package | Count |
| --- | --- |
| go | 11 |
| podman | 6 |
| plugins | 6 |
| kubernetes | 6 |
| common | 6 |
| dataplaneapi | 2 |
| etcd | 1 |

### Top 10 Packages with HIGH issues in category "Cross-site Scripting (XSS)" (category total=37)

| Package | Count |
| --- | --- |
| kapacitor | 15 |
| uwsgi | 4 |
| freetds | 4 |
| zookeeper | 2 |
| gevent | 2 |
| buildx | 2 |
| tornado | 1 |
| runtime | 1 |
| rabbitmq-server | 1 |
| kubernetes | 1 |

### Top 10 Packages with HIGH issues in category "Size Used as Index" (category total=36)

| Package | Count |
| --- | --- |
| mysql-server | 17 |
| src | 3 |
| protobuf | 3 |
| leveldb | 3 |
| llvm-project | 2 |
| kexec-tools | 2 |
| u-boot | 1 |
| pmd-next-gen | 1 |
| node | 1 |
| libqmi | 1 |

### Top 10 Packages with HIGH issues in category "Hardcoded Non-Cryptographic Secret" (category total=33)

| Package | Count |
| --- | --- |
| python | 14 |
| tornado | 5 |
| node | 5 |
| rabbitmq-server | 2 |
| uwsgi | 1 |
| pyzmq | 1 |
| pydantic | 1 |
| pycryptodome | 1 |
| gevent | 1 |
| cloud-init | 1 |

### Top 10 Packages with HIGH issues in category "XML External Entity (XXE) Injection" (category total=29)

| Package | Count |
| --- | --- |
| xmlsec | 14 |
| xerces-c | 7 |
| libxslt | 6 |
| runtime | 1 |
| libxml2 | 1 |


## Top 10 Source Packages with most issues (with breakdown)

| Package | TotalIssues | HighCrypto | High | Medium | Low |
| --- | --- | --- | --- | --- | --- |
| jdk21u | 2997 | 54 | 105 | 727 | 2165 |
| jdk11u | 2855 | 54 | 105 | 785 | 1965 |
| llvm-project | 2775 | 0 | 39 | 445 | 2291 |
| node | 2744 | 5 | 23 | 422 | 2299 |
| jdk17u | 2733 | 53 | 101 | 675 | 1957 |
| runtime | 1990 | 20 | 28 | 240 | 1722 |
| subversion | 1470 | 0 | 0 | 49 | 1421 |
| mysql-server | 1343 | 1 | 27 | 608 | 708 |
| wireshark | 1140 | 0 | 6 | 167 | 967 |
| src | 992 | 0 | 6 | 696 | 290 |


## Top 10 Source Packages with most issues on Level "High (+ crypto)"

| Package | Count |
| --- | --- |
| jdk21u | 54 |
| jdk11u | 54 |
| jdk17u | 53 |
| runtime | 20 |
| python | 14 |
| tornado | 5 |
| node | 5 |
| pycryptodome | 4 |
| unbound | 2 |
| rabbitmq-server | 2 |


## Top 10 Source Packages with most issues on Level "High"

| Package | Count |
| --- | --- |
| jdk21u | 105 |
| jdk11u | 105 |
| jdk17u | 101 |
| llvm-project | 39 |
| go | 34 |
| runtime | 28 |
| podman | 28 |
| mysql-server | 27 |
| node | 23 |
| common | 21 |


## Top 10 Source Packages with most issues on Level "Medium"

| Package | Count |
| --- | --- |
| jdk11u | 785 |
| jdk21u | 727 |
| src | 696 |
| jdk17u | 675 |
| mysql-server | 608 |
| cups | 588 |
| util-linux | 488 |
| server | 481 |
| crash | 467 |
| llvm-project | 445 |


## Top 10 Source Packages with most issues on Level "Low"

| Package | Count |
| --- | --- |
| node | 2299 |
| llvm-project | 2291 |
| jdk21u | 2165 |
| jdk11u | 1965 |
| jdk17u | 1957 |
| runtime | 1722 |
| subversion | 1421 |
| wireshark | 967 |
| zsh | 738 |
| mysql-server | 708 |


## Processing status (branch 5.0)

| Step | Detail |
|---|---|
| SAST scan | ok (691 subdirs) |
| Agent-scan coverage | configs found=19, scans run=2, failed=0 |

## Agent Components (snyk-agent-scan)

| Metric | Count |
|---|---|
| Scans | 20 |
| Packages scanned | 17 |
| Total issues | 0 |
| High / Critical | 0 |
| Medium | 0 |
| Low / Info | 0 |

### Coverage by agent type

| AgentType | Packages | Issues |
| --- | --- | --- |
| claude | 7 | 0 |
| cursor | 1 | 0 |
| gemini | 10 | 0 |


### Top 10 Agent-Component Issue Codes

(none)


### Top 10 Packages with Agent-Component Issues

(none)

