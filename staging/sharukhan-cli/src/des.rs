//! Single-block DES encryption, for RFB "VNC Authentication" only.
//!
//! RFB 3.8 section 7.2.2: the server sends a 16-byte challenge, the client
//! returns it DES-encrypted (ECB, two blocks) under the password, truncated or
//! zero-padded to 8 bytes, with the bits of every key byte reversed. DES is
//! not a protection here and is not used as one: the console listens only on
//! the host's WSL-facing address, and the password keeps a second process on
//! that host from typing into a guest it did not start. Nothing else in the
//! harness may use this module.

const IP: [u8; 64] = [
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4, 62, 54, 46, 38, 30, 22, 14, 6,
    64, 56, 48, 40, 32, 24, 16, 8, 57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3, 61,
    53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
];
const FP: [u8; 64] = [
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29, 36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27, 34,
    2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25,
];
const E: [u8; 48] = [
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 16, 17, 16, 17, 18,
    19, 20, 21, 20, 21, 22, 23, 24, 25, 24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
];
const P: [u8; 32] = [
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10, 2, 8, 24, 14, 32, 27, 3, 9, 19, 13,
    30, 6, 22, 11, 4, 25,
];
const PC1: [u8; 56] = [
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, 10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60,
    52, 44, 36, 63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37, 29,
    21, 13, 5, 28, 20, 12, 4,
];
const PC2: [u8; 48] = [
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10, 23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2, 41, 52,
    31, 37, 47, 55, 30, 40, 51, 45, 33, 48, 44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
];
const SHIFTS: [u32; 16] = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];
const S: [[u8; 64]; 8] = [
    [
        14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, 0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12,
        11, 9, 5, 3, 8, 4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, 15, 12, 8, 2, 4, 9, 1,
        7, 5, 11, 3, 14, 10, 0, 6, 13,
    ],
    [
        15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, 3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1,
        10, 6, 9, 11, 5, 0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, 13, 8, 10, 1, 3, 15,
        4, 2, 11, 6, 7, 12, 0, 5, 14, 9,
    ],
    [
        10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, 13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14,
        12, 11, 15, 1, 13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, 1, 10, 13, 0, 6, 9, 8,
        7, 4, 15, 14, 3, 11, 5, 2, 12,
    ],
    [
        7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, 13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12,
        1, 10, 14, 9, 10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, 3, 15, 0, 6, 10, 1, 13,
        8, 9, 4, 5, 11, 12, 7, 2, 14,
    ],
    [
        2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, 14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15,
        10, 3, 9, 8, 6, 4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, 11, 8, 12, 7, 1, 14, 2,
        13, 6, 15, 0, 9, 10, 4, 5, 3,
    ],
    [
        12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, 10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13,
        14, 0, 11, 3, 8, 9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, 4, 3, 2, 12, 9, 5, 15,
        10, 11, 14, 1, 7, 6, 0, 8, 13,
    ],
    [
        4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, 13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5,
        12, 2, 15, 8, 6, 1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, 6, 11, 13, 8, 1, 4,
        10, 7, 9, 5, 0, 15, 14, 2, 3, 12,
    ],
    [
        13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, 1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6,
        11, 0, 14, 9, 2, 7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, 2, 1, 14, 7, 4, 10, 8,
        13, 15, 12, 9, 0, 3, 5, 6, 11,
    ],
];

/// Select bits of `v` (an `width`-bit value, bit 1 = most significant) in the
/// order `table` names them.
fn permute(v: u64, width: u32, table: &[u8]) -> u64 {
    table
        .iter()
        .fold(0u64, |acc, &b| (acc << 1) | ((v >> (width - b as u32)) & 1))
}

fn subkeys(key: u64) -> [u64; 16] {
    let cd = permute(key, 64, &PC1);
    let (mut c, mut d) = ((cd >> 28) as u32 & 0x0fff_ffff, cd as u32 & 0x0fff_ffff);
    let rot = |x: u32, n: u32| ((x << n) | (x >> (28 - n))) & 0x0fff_ffff;
    let mut k = [0u64; 16];
    for (i, s) in SHIFTS.iter().enumerate() {
        c = rot(c, *s);
        d = rot(d, *s);
        k[i] = permute(((c as u64) << 28) | d as u64, 56, &PC2);
    }
    k
}

fn feistel(r: u32, k: u64) -> u32 {
    let x = permute(r as u64, 32, &E) ^ k;
    let mut out = 0u32;
    for (i, sbox) in S.iter().enumerate() {
        let six = ((x >> (42 - 6 * i)) & 0x3f) as usize;
        let row = ((six & 0x20) >> 4) | (six & 1);
        let col = (six >> 1) & 0xf;
        out = (out << 4) | sbox[row * 16 + col] as u32;
    }
    permute(out as u64, 32, &P) as u32
}

/// Encrypt one 8-byte block under an 8-byte key, as FIPS 46-3 defines it.
pub fn encrypt_block(key: [u8; 8], block: [u8; 8]) -> [u8; 8] {
    let ks = subkeys(u64::from_be_bytes(key));
    let b = permute(u64::from_be_bytes(block), 64, &IP);
    let (mut l, mut r) = ((b >> 32) as u32, b as u32);
    for k in ks {
        let t = r;
        r = l ^ feistel(r, k);
        l = t;
    }
    permute(((r as u64) << 32) | l as u64, 64, &FP).to_be_bytes()
}

/// The RFB VNC-Authentication response to `challenge` under `password`.
pub fn vnc_response(password: &[u8], challenge: &[u8; 16]) -> [u8; 16] {
    let mut key = [0u8; 8];
    for (k, p) in key.iter_mut().zip(password.iter()) {
        *k = p.reverse_bits();
    }
    let mut out = [0u8; 16];
    for (i, chunk) in challenge.chunks_exact(8).enumerate() {
        let mut blk = [0u8; 8];
        blk.copy_from_slice(chunk);
        out[i * 8..i * 8 + 8].copy_from_slice(&encrypt_block(key, blk));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> [u8; 8] {
        let mut b = [0u8; 8];
        for i in 0..8 {
            b[i] = u8::from_str_radix(&s[2 * i..2 * i + 2], 16).unwrap();
        }
        b
    }

    /// FIPS 81 appendix B and the NBS/NIST validation vectors: a DES that
    /// gets one table entry wrong fails at least one of these.
    #[test]
    fn known_answer_vectors() {
        let cases = [
            ("0123456789ABCDEF", "4E6F772069732074", "3FA40E8A984D4815"),
            ("133457799BBCDFF1", "0123456789ABCDEF", "85E813540F0AB405"),
            ("0000000000000000", "0000000000000000", "8CA64DE9C1B123A7"),
            ("FFFFFFFFFFFFFFFF", "FFFFFFFFFFFFFFFF", "7359B2163E4EDC58"),
            ("3000000000000000", "1000000000000001", "958E6E627A05557B"),
            ("1111111111111111", "1111111111111111", "F40379AB9E0EC533"),
            ("0123456789ABCDEF", "1111111111111111", "17668DFC7292532D"),
            ("FEDCBA9876543210", "0123456789ABCDEF", "ED39D950FA74BCC4"),
        ];
        for (k, p, c) in cases {
            assert_eq!(encrypt_block(hex(k), hex(p)), hex(c), "key {k} plain {p}");
        }
    }

    /// The RFB key is the password with each byte's bits reversed, zero
    /// padded: "\x80" reverses to 0x01, so it must encrypt like key 01000000..
    #[test]
    fn the_vnc_key_reverses_bits_and_pads_with_zero() {
        let ch = [0u8; 16];
        let r = vnc_response(b"\x80", &ch);
        let want = encrypt_block(hex("0100000000000000"), [0u8; 8]);
        assert_eq!(&r[..8], &want);
        assert_eq!(&r[8..], &want);
    }
}
