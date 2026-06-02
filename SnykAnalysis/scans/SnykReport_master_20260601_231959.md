# Snyk Issues Report (master)

Generated: 06/02/2026 01:20:25
Total source packages processed: 693
Tool used: SnykCLI

## Summary

| Metric | Count |
|---|---|
| Total issues overall | 60987 |
| High with crypto | 246 |
| High without crypto | 756 |
| Medium | 22739 |
| Low | 37246 |

## Top 10 High Categories

| Category | Count |
| --- | --- |
| Use of a Broken or Risky Cryptographic Algorithm | 193 |
| Hardcoded Secret | 132 |
| Cross-site Scripting (XSS) | 129 |
| Potential Negative Number Used as Index | 117 |
| Path Traversal | 90 |
| Command Injection | 65 |
| Hardcoded Non-Cryptographic Secret | 48 |
| Generation of Error Message Containing Sensitive Information | 38 |
| Size Used as Index | 35 |
| XML External Entity (XXE) Injection | 33 |


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

### Top 10 Packages with HIGH issues in category "Hardcoded Secret" (category total=132)

| Package | Count |
| --- | --- |
| jdk11u | 44 |
| jdk21u | 43 |
| jdk17u | 42 |
| tomcat | 1 |
| runtime | 1 |
| kafka | 1 |

### Top 10 Packages with HIGH issues in category "Cross-site Scripting (XSS)" (category total=129)

| Package | Count |
| --- | --- |
| tomcat | 92 |
| kapacitor | 15 |
| uwsgi | 4 |
| freetds | 4 |
| gevent | 2 |
| zookeeper | 1 |
| tornado | 1 |
| telegraf | 1 |
| runtime | 1 |
| rabbitmq-server | 1 |

### Top 10 Packages with HIGH issues in category "Potential Negative Number Used as Index" (category total=117)

| Package | Count |
| --- | --- |
| llvm-project | 35 |
| wireshark | 6 |
| redis | 6 |
| server | 5 |
| mysql-server | 5 |
| node | 4 |
| ntp | 3 |
| libxcrypt | 3 |
| systemtap | 2 |
| ruby | 2 |

### Top 10 Packages with HIGH issues in category "Path Traversal" (category total=90)

| Package | Count |
| --- | --- |
| tomcat | 25 |
| ruby | 18 |
| podman | 8 |
| govmomi | 7 |
| telegraf | 6 |
| runtime | 3 |
| go | 3 |
| common | 3 |
| src | 2 |
| moby | 2 |

### Top 10 Packages with HIGH issues in category "Command Injection" (category total=65)

| Package | Count |
| --- | --- |
| go | 22 |
| podman | 8 |
| common | 7 |
| termshark | 4 |
| etcd | 4 |
| containerd | 4 |
| moby | 3 |
| libcap | 3 |
| heapster | 2 |
| tomcat | 1 |

### Top 10 Packages with HIGH issues in category "Hardcoded Non-Cryptographic Secret" (category total=48)

| Package | Count |
| --- | --- |
| python | 28 |
| tornado | 5 |
| node | 5 |
| rabbitmq-server | 2 |
| uwsgi | 1 |
| pyzmq | 1 |
| pydantic | 1 |
| pycryptodome | 1 |
| psutil | 1 |
| gevent | 1 |

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

### Top 10 Packages with HIGH issues in category "Size Used as Index" (category total=35)

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
| libqmi | 1 |
| geos | 1 |

### Top 10 Packages with HIGH issues in category "XML External Entity (XXE) Injection" (category total=33)

| Package | Count |
| --- | --- |
| xmlsec | 14 |
| xerces-c | 7 |
| libxslt | 6 |
| tomcat | 4 |
| runtime | 1 |
| libxml2 | 1 |


## Top 10 Source Packages with most issues (with breakdown)

| Package | TotalIssues | HighCrypto | High | Medium | Low |
| --- | --- | --- | --- | --- | --- |
| jdk21u | 2983 | 54 | 105 | 712 | 2166 |
| node | 2838 | 5 | 22 | 429 | 2387 |
| llvm-project | 2829 | 0 | 39 | 450 | 2340 |
| jdk11u | 2823 | 54 | 105 | 770 | 1948 |
| jdk17u | 2714 | 53 | 101 | 660 | 1953 |
| runtime | 2008 | 20 | 28 | 241 | 1739 |
| subversion | 1471 | 0 | 0 | 49 | 1422 |
| mysql-server | 1343 | 1 | 27 | 608 | 708 |
| wireshark | 1144 | 0 | 6 | 170 | 968 |
| src | 1004 | 0 | 6 | 708 | 290 |


## Top 10 Source Packages with most issues on Level "High (+ crypto)"

| Package | Count |
| --- | --- |
| jdk21u | 54 |
| jdk11u | 54 |
| jdk17u | 53 |
| python | 28 |
| runtime | 20 |
| tornado | 5 |
| node | 5 |
| pycryptodome | 4 |
| unbound | 2 |
| rabbitmq-server | 2 |


## Top 10 Source Packages with most issues on Level "High"

| Package | Count |
| --- | --- |
| tomcat | 129 |
| jdk21u | 105 |
| jdk11u | 105 |
| jdk17u | 101 |
| llvm-project | 39 |
| go | 37 |
| runtime | 28 |
| python | 28 |
| podman | 28 |
| mysql-server | 27 |


## Top 10 Source Packages with most issues on Level "Medium"

| Package | Count |
| --- | --- |
| jdk11u | 770 |
| jdk21u | 712 |
| src | 708 |
| jdk17u | 660 |
| aufs-linux | 654 |
| mysql-server | 608 |
| cups | 592 |
| util-linux | 493 |
| server | 478 |
| crash | 467 |


## Top 10 Source Packages with most issues on Level "Low"

| Package | Count |
| --- | --- |
| node | 2387 |
| llvm-project | 2340 |
| jdk21u | 2166 |
| jdk17u | 1953 |
| jdk11u | 1948 |
| runtime | 1739 |
| subversion | 1422 |
| wireshark | 968 |
| zsh | 737 |
| mysql-server | 708 |


## Processing status (branch master)

| Step | Detail |
|---|---|
| SAST scan | ok (693 subdirs) |
| Agent-scan coverage | configs found=20, scans run=19, failed=0 |

## Agent Components (snyk-agent-scan)

| Metric | Count |
|---|---|
| Scans | 19 |
| Packages scanned | 18 |
| Total issues | 0 |
| High / Critical | 0 |
| Medium | 0 |
| Low / Info | 0 |

### Coverage by agent type

| AgentType | Packages | Issues |
| --- | --- | --- |
| claude | 9 | 0 |
| codex | 1 | 0 |
| gemini | 9 | 0 |


### Top 10 Agent-Component Issue Codes

(none)


### Top 10 Packages with Agent-Component Issues

(none)

