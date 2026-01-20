#!/bin/bash
# HAB Keys Management - Generate and manage cryptographic keys
# Includes UEFI Secure Boot keys, MOK, and module signing keys

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hab_lib.sh"

# ============================================================================
# Key Configuration
# ============================================================================

# Key validity period (10 years)
KEY_VALIDITY_DAYS=3650

# Key sizes
SRK_KEY_SIZE=4096
CSF_KEY_SIZE=2048
IMG_KEY_SIZE=2048
UEFI_KEY_SIZE=2048

# Certificate subjects
PK_SUBJECT="/CN=Photon OS Platform Key/O=VMware/C=US"
KEK_SUBJECT="/CN=Photon OS Key Exchange Key/O=VMware/C=US"
DB_SUBJECT="/CN=Photon OS Signature Database Key/O=VMware/C=US"
MOK_SUBJECT="/CN=Photon OS Secure Boot MOK/O=VMware/C=US"
MODULE_SUBJECT="/CN=Photon OS Kernel Module Signing Key/O=VMware/C=US"

# ============================================================================
# Key Generation Functions
# ============================================================================

generate_all_keys() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    
    log_step "Generating all cryptographic keys..."
    ensure_dir "$keys_dir"
    
    generate_hab_keys "$keys_dir"
    generate_uefi_keys "$keys_dir"
    generate_mok_key "$keys_dir"
    generate_module_signing_key "$keys_dir"
    
    log_ok "All keys generated in $keys_dir"
}

generate_hab_keys() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    
    log_step "Generating HAB keys (SRK, CSF, IMG)..."
    ensure_dir "$keys_dir"
    
    # Super Root Key (SRK) - 4096-bit RSA
    if [[ ! -f "$keys_dir/srk.pem" ]]; then
        openssl genrsa -out "$keys_dir/srk.pem" $SRK_KEY_SIZE 2>/dev/null
        openssl rsa -in "$keys_dir/srk.pem" -pubout -out "$keys_dir/srk_pub.pem" 2>/dev/null
        openssl dgst -sha256 -binary "$keys_dir/srk_pub.pem" > "$keys_dir/srk_hash.bin"
        log_ok "Generated SRK (${SRK_KEY_SIZE}-bit)"
    fi
    
    # CSF Key - 2048-bit RSA
    if [[ ! -f "$keys_dir/csf.pem" ]]; then
        openssl genrsa -out "$keys_dir/csf.pem" $CSF_KEY_SIZE 2>/dev/null
        openssl rsa -in "$keys_dir/csf.pem" -pubout -out "$keys_dir/csf_pub.pem" 2>/dev/null
        log_ok "Generated CSF key (${CSF_KEY_SIZE}-bit)"
    fi
    
    # IMG Key - 2048-bit RSA
    if [[ ! -f "$keys_dir/img.pem" ]]; then
        openssl genrsa -out "$keys_dir/img.pem" $IMG_KEY_SIZE 2>/dev/null
        openssl rsa -in "$keys_dir/img.pem" -pubout -out "$keys_dir/img_pub.pem" 2>/dev/null
        log_ok "Generated IMG key (${IMG_KEY_SIZE}-bit)"
    fi
}

generate_uefi_keys() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    
    log_step "Generating UEFI Secure Boot keys (PK, KEK, DB)..."
    ensure_dir "$keys_dir"
    
    # Platform Key (PK)
    if [[ ! -f "$keys_dir/PK.key" ]]; then
        openssl req -new -x509 -newkey rsa:$UEFI_KEY_SIZE -nodes \
            -keyout "$keys_dir/PK.key" -out "$keys_dir/PK.crt" \
            -days $KEY_VALIDITY_DAYS -subj "$PK_SUBJECT" 2>/dev/null
        openssl x509 -in "$keys_dir/PK.crt" -outform DER -out "$keys_dir/PK.der"
        log_ok "Generated Platform Key (PK)"
    fi
    
    # Key Exchange Key (KEK)
    if [[ ! -f "$keys_dir/KEK.key" ]]; then
        openssl req -new -x509 -newkey rsa:$UEFI_KEY_SIZE -nodes \
            -keyout "$keys_dir/KEK.key" -out "$keys_dir/KEK.crt" \
            -days $KEY_VALIDITY_DAYS -subj "$KEK_SUBJECT" 2>/dev/null
        openssl x509 -in "$keys_dir/KEK.crt" -outform DER -out "$keys_dir/KEK.der"
        log_ok "Generated Key Exchange Key (KEK)"
    fi
    
    # Signature Database Key (DB)
    if [[ ! -f "$keys_dir/DB.key" ]]; then
        openssl req -new -x509 -newkey rsa:$UEFI_KEY_SIZE -nodes \
            -keyout "$keys_dir/DB.key" -out "$keys_dir/DB.crt" \
            -days $KEY_VALIDITY_DAYS -subj "$DB_SUBJECT" 2>/dev/null
        openssl x509 -in "$keys_dir/DB.crt" -outform DER -out "$keys_dir/DB.der"
        log_ok "Generated Signature Database Key (DB)"
    fi
}

generate_mok_key() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    
    log_step "Generating Machine Owner Key (MOK)..."
    ensure_dir "$keys_dir"
    
    if [[ ! -f "$keys_dir/MOK.key" ]]; then
        openssl req -new -x509 -newkey rsa:$UEFI_KEY_SIZE -nodes \
            -keyout "$keys_dir/MOK.key" -out "$keys_dir/MOK.crt" \
            -days $KEY_VALIDITY_DAYS -subj "$MOK_SUBJECT" 2>/dev/null
        openssl x509 -in "$keys_dir/MOK.crt" -outform DER -out "$keys_dir/MOK.der"
        log_ok "Generated Machine Owner Key (MOK)"
    fi
}

generate_module_signing_key() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    
    log_step "Generating kernel module signing key..."
    ensure_dir "$keys_dir"
    
    if [[ ! -f "$keys_dir/kernel_module_signing.pem" ]]; then
        # Create OpenSSL config for module signing
        local conf_file="$keys_dir/module_signing.conf"
        cat > "$conf_file" << 'EOF'
[ req ]
default_bits = 4096
distinguished_name = req_distinguished_name
prompt = no
string_mask = utf8only
x509_extensions = myexts

[ req_distinguished_name ]
O = Photon OS
CN = Photon OS Kernel Module Signing Key
emailAddress = security@photon.local

[ myexts ]
basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
        
        openssl req -new -nodes -utf8 -sha256 -days $KEY_VALIDITY_DAYS \
            -batch -x509 -config "$conf_file" \
            -outform PEM -out "$keys_dir/kernel_module_signing.pem" \
            -keyout "$keys_dir/kernel_module_signing.pem" 2>/dev/null
        
        rm -f "$conf_file"
        log_ok "Generated kernel module signing key"
    fi
}

# ============================================================================
# Key Verification Functions
# ============================================================================

verify_keys() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    local errors=0
    
    log_step "Verifying keys..."
    
    # Check HAB keys
    for key in srk csf img; do
        if [[ ! -f "$keys_dir/${key}.pem" ]]; then
            log_error "Missing HAB key: ${key}.pem"
            ((errors++))
        fi
    done
    
    # Check UEFI keys
    for key in PK KEK DB; do
        if [[ ! -f "$keys_dir/${key}.key" || ! -f "$keys_dir/${key}.crt" ]]; then
            log_error "Missing UEFI key: ${key}"
            ((errors++))
        fi
    done
    
    # Check MOK
    if [[ ! -f "$keys_dir/MOK.key" || ! -f "$keys_dir/MOK.crt" ]]; then
        log_error "Missing MOK key"
        ((errors++))
    fi
    
    # Check module signing key
    if [[ ! -f "$keys_dir/kernel_module_signing.pem" ]]; then
        log_error "Missing kernel module signing key"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_ok "All keys verified"
        return 0
    else
        log_error "$errors key(s) missing or invalid"
        return 1
    fi
}

list_keys() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    
    echo ""
    echo "=== HAB Keys Directory: $keys_dir ==="
    echo ""
    
    if [[ ! -d "$keys_dir" ]]; then
        echo "Keys directory does not exist"
        return 1
    fi
    
    echo "HAB Keys:"
    for key in srk csf img; do
        if [[ -f "$keys_dir/${key}.pem" ]]; then
            echo "  [OK] ${key}.pem ($(stat -c%s "$keys_dir/${key}.pem") bytes)"
        else
            echo "  [--] ${key}.pem (missing)"
        fi
    done
    
    echo ""
    echo "UEFI Secure Boot Keys:"
    for key in PK KEK DB; do
        if [[ -f "$keys_dir/${key}.key" ]]; then
            echo "  [OK] ${key}.key/.crt/.der"
        else
            echo "  [--] ${key} (missing)"
        fi
    done
    
    echo ""
    echo "Machine Owner Key (MOK):"
    if [[ -f "$keys_dir/MOK.key" ]]; then
        echo "  [OK] MOK.key/.crt/.der"
        echo "       Subject: $(openssl x509 -in "$keys_dir/MOK.crt" -noout -subject 2>/dev/null | sed 's/subject=//')"
    else
        echo "  [--] MOK (missing)"
    fi
    
    echo ""
    echo "Kernel Module Signing Key:"
    if [[ -f "$keys_dir/kernel_module_signing.pem" ]]; then
        echo "  [OK] kernel_module_signing.pem"
    else
        echo "  [--] kernel_module_signing.pem (missing)"
    fi
    
    echo ""
    echo "Shim Files:"
    for shim in shim-suse.efi shim-fedora.efi; do
        if [[ -f "$keys_dir/$shim" ]]; then
            local sbat
            sbat=$(get_sbat_version "$keys_dir/$shim" 2>/dev/null || echo "unknown")
            echo "  [OK] $shim (SBAT: $sbat)"
        fi
    done
    
    for mok in MokManager-suse.efi mmx64-fedora.efi; do
        if [[ -f "$keys_dir/$mok" ]]; then
            echo "  [OK] $mok"
        fi
    done
    
    echo ""
}

# ============================================================================
# Main (when run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-generate}" in
        generate)
            generate_all_keys "${2:-$HAB_KEYS_DIR}"
            ;;
        verify)
            verify_keys "${2:-$HAB_KEYS_DIR}"
            ;;
        list)
            list_keys "${2:-$HAB_KEYS_DIR}"
            ;;
        *)
            echo "Usage: $0 {generate|verify|list} [keys_dir]"
            exit 1
            ;;
    esac
fi
