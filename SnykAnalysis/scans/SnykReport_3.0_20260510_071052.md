# Snyk Issues Report (3.0)

Generated: 05/10/2026 09:10:57
Total source packages processed: 583
Tool used: SnykCLI

## Summary

| Metric | Count |
|---|---|
| Total issues overall | 57840 |
| High with crypto | 302 |
| High without crypto | 864 |
| Medium | 20246 |
| Low | 36428 |

## Top 10 High Categories

| Category | Count |
| --- | --- |
| Use of a Broken or Risky Cryptographic Algorithm | 245 |
| Hardcoded Secret | 169 |
| Cross-site Scripting (XSS) | 126 |
| Potential Negative Number Used as Index | 114 |
| Path Traversal | 88 |
| Regular Expression Denial of Service (ReDoS) | 72 |
| DOM-based Cross-site Scripting (XSS) | 61 |
| Hardcoded Non-Cryptographic Secret | 53 |
| Size Used as Index | 36 |
| XML External Entity (XXE) Injection | 35 |


### Top 10 Packages with HIGH issues in category "Use of a Broken or Risky Cryptographic Algorithm" (category total=245)

| Package | Count |
| --- | --- |
| jdk8u | 54 |
| jdk11u | 54 |
| jdk10u | 54 |
| jdk17u | 53 |
| runtime | 19 |
| pycryptodome | 3 |
| elasticsearch | 2 |
| apr-util | 2 |
| apr | 2 |
| mysql-server | 1 |

### Top 10 Packages with HIGH issues in category "Hardcoded Secret" (category total=169)

| Package | Count |
| --- | --- |
| jdk11u | 44 |
| jdk17u | 42 |
| jdk8u | 37 |
| jdk10u | 34 |
| elasticsearch | 7 |
| lightwave | 2 |
| tomcat | 1 |
| runtime | 1 |
| kafka | 1 |

### Top 10 Packages with HIGH issues in category "Cross-site Scripting (XSS)" (category total=126)

| Package | Count |
| --- | --- |
| tomcat | 90 |
| kapacitor | 15 |
| lightwave | 5 |
| freetds | 4 |
| gevent | 2 |
| tornado | 1 |
| tiptop | 1 |
| runtime | 1 |
| rabbitmq-server | 1 |
| kubernetes | 1 |

### Top 10 Packages with HIGH issues in category "Potential Negative Number Used as Index" (category total=114)

| Package | Count |
| --- | --- |
| llvm-project | 35 |
| wireshark | 6 |
| redis | 6 |
| lightwave | 6 |
| server | 5 |
| mysql-server | 5 |
| node | 4 |
| nvme-cli | 3 |
| ntp | 3 |
| systemtap | 2 |

### Top 10 Packages with HIGH issues in category "Path Traversal" (category total=88)

| Package | Count |
| --- | --- |
| tomcat | 40 |
| ruby | 18 |
| govmomi | 7 |
| telegraf | 6 |
| runtime | 3 |
| src | 2 |
| moby | 2 |
| llvm-project | 2 |
| git-lfs | 2 |
| urllib3 | 1 |

### Top 10 Packages with HIGH issues in category "Regular Expression Denial of Service (ReDoS)" (category total=72)

| Package | Count |
| --- | --- |
| kibana | 60 |
| node | 12 |

### Top 10 Packages with HIGH issues in category "DOM-based Cross-site Scripting (XSS)" (category total=61)

| Package | Count |
| --- | --- |
| kibana | 60 |
| asciidoc3 | 1 |

### Top 10 Packages with HIGH issues in category "Hardcoded Non-Cryptographic Secret" (category total=53)

| Package | Count |
| --- | --- |
| kibana | 35 |
| tornado | 5 |
| node | 5 |
| rabbitmq-server | 2 |
| pyzmq | 1 |
| pydantic | 1 |
| pycryptodome | 1 |
| gevent | 1 |
| cloud-init | 1 |
| WALinuxAgent | 1 |

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
| pmd | 1 |
| node | 1 |
| libqmi | 1 |

### Top 10 Packages with HIGH issues in category "XML External Entity (XXE) Injection" (category total=35)

| Package | Count |
| --- | --- |
| xmlsec | 14 |
| xerces-c | 7 |
| libxslt | 6 |
| tomcat | 4 |
| lightwave | 2 |
| runtime | 1 |
| libxml2 | 1 |


## Top 10 Source Packages with most issues (with breakdown)

| Package | TotalIssues | HighCrypto | High | Medium | Low |
| --- | --- | --- | --- | --- | --- |
| jdk11u | 2855 | 54 | 105 | 785 | 1965 |
| llvm-project | 2775 | 0 | 39 | 445 | 2291 |
| node | 2744 | 5 | 23 | 422 | 2299 |
| jdk17u | 2733 | 53 | 101 | 675 | 1957 |
| jdk10u | 2462 | 54 | 95 | 691 | 1676 |
| jdk8u | 2347 | 54 | 97 | 844 | 1406 |
| runtime | 1990 | 20 | 28 | 240 | 1722 |
| kibana | 1874 | 35 | 169 | 159 | 1546 |
| subversion | 1470 | 0 | 0 | 49 | 1421 |
| elasticsearch | 1448 | 2 | 16 | 81 | 1351 |


## Top 10 Source Packages with most issues on Level "High (+ crypto)"

| Package | Count |
| --- | --- |
| jdk8u | 54 |
| jdk11u | 54 |
| jdk10u | 54 |
| jdk17u | 53 |
| kibana | 35 |
| runtime | 20 |
| tornado | 5 |
| node | 5 |
| pycryptodome | 4 |
| unbound | 2 |


## Top 10 Source Packages with most issues on Level "High"

| Package | Count |
| --- | --- |
| kibana | 169 |
| tomcat | 142 |
| jdk11u | 105 |
| jdk17u | 101 |
| jdk8u | 97 |
| jdk10u | 95 |
| llvm-project | 39 |
| lightwave | 29 |
| runtime | 28 |
| mysql-server | 27 |


## Top 10 Source Packages with most issues on Level "Medium"

| Package | Count |
| --- | --- |
| jdk8u | 844 |
| jdk11u | 785 |
| src | 696 |
| jdk10u | 691 |
| jdk17u | 675 |
| mysql-server | 608 |
| util-linux | 488 |
| server | 481 |
| crash | 467 |
| llvm-project | 445 |


## Top 10 Source Packages with most issues on Level "Low"

| Package | Count |
| --- | --- |
| node | 2299 |
| llvm-project | 2291 |
| jdk11u | 1965 |
| jdk17u | 1957 |
| runtime | 1722 |
| jdk10u | 1676 |
| kibana | 1546 |
| subversion | 1421 |
| jdk8u | 1406 |
| elasticsearch | 1351 |

