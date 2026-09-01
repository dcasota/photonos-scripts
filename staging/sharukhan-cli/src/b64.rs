//! Standard base64, encode only.
//!
//! POI's isoInstaller reads `guestinfo.kickstart.data` as base64 via vmtoolsd,
//! so exactly one string in this program needs encoding. The bash shelled out
//! to `base64 -w0`; a dependency for 20 lines would be a worse trade than the
//! 20 lines.

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Single-line output. `base64 -w0` is what the VMX line has always carried;
/// wrapping it would put a newline inside a quoted VMX value.
pub fn encode(input: &[u8]) -> String {
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    for chunk in input.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(ALPHABET[(n >> 18) as usize & 63] as char);
        out.push(ALPHABET[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            ALPHABET[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RFC 4648 section 10.
    #[test]
    fn known_vectors() {
        assert_eq!(encode(b""), "");
        assert_eq!(encode(b"f"), "Zg==");
        assert_eq!(encode(b"fo"), "Zm8=");
        assert_eq!(encode(b"foo"), "Zm9v");
        assert_eq!(encode(b"foob"), "Zm9vYg==");
        assert_eq!(encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn binary_and_high_bytes() {
        assert_eq!(encode(&[0xff, 0xff, 0xff]), "////");
        assert_eq!(encode(&[0x00, 0x00, 0x00]), "AAAA");
        assert_eq!(encode(&[0xfb, 0xff]), "+/8=");
    }

    /// The real shape: a kickstart is JSON, and the encoded form must be one
    /// line because it becomes a quoted VMX value.
    #[test]
    fn a_kickstart_sized_payload_stays_on_one_line() {
        let ks = "{\"hostname\": \"mc-k01\"}\n".repeat(200);
        let e = encode(ks.as_bytes());
        assert!(!e.contains('\n'));
        assert_eq!(e.len(), ks.len().div_ceil(3) * 4);
    }
}
