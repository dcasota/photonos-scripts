//! The VM's console, through the VNC server VMware builds into the VMX.
//!
//! Only what pressing a key at a boot menu needs: RFB 3.8 with VNC
//! Authentication, one full raw framebuffer read, and a key event. Each call
//! opens its own connection, because a mode switch (BIOS logo, loader text,
//! menu graphics, kernel console) changes the framebuffer size, and a
//! connection that negotiated the old size has to be reopened anyway.
//!
//! vmcli's `MKS sendKeyEvent` was tried first: it returns 0 and the guest
//! never sees the key (VMware Workstation 25H2, build 25688693, logs nothing
//! for it), so it cannot be used.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

/// X11 keysym for Return, what RFB KeyEvent carries.
pub const XK_RETURN: u32 = 0xff0d;

/// Where a VM's console listens and the password it takes.
#[derive(Clone)]
pub struct Endpoint {
    pub addr: SocketAddr,
    pub password: String,
}

/// One look at the screen.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub width: u16,
    pub height: u16,
    /// The desktop name, which VMware sets to the VM's displayName.
    pub name: String,
    /// FNV-1a over the raw pixels: equal frames are equal screens.
    pub digest: u64,
}

struct Session {
    sock: TcpStream,
    width: u16,
    height: u16,
    bpp: u8,
    name: String,
}

fn rx(s: &mut TcpStream, n: usize) -> Result<Vec<u8>, String> {
    let mut b = vec![0u8; n];
    s.read_exact(&mut b).map_err(|e| format!("console read: {e}"))?;
    Ok(b)
}

fn tx(s: &mut TcpStream, b: &[u8]) -> Result<(), String> {
    s.write_all(b).map_err(|e| format!("console write: {e}"))
}

fn be32(b: &[u8]) -> u32 {
    u32::from_be_bytes([b[0], b[1], b[2], b[3]])
}

fn open(ep: &Endpoint, timeout: Duration) -> Result<Session, String> {
    let mut s = TcpStream::connect_timeout(&ep.addr, timeout)
        .map_err(|e| format!("console {}: {e}", ep.addr))?;
    let _ = s.set_read_timeout(Some(timeout));
    let _ = s.set_write_timeout(Some(timeout));
    let ver = rx(&mut s, 12)?;
    if !ver.starts_with(b"RFB 003.") {
        return Err(format!(
            "console {} is not an RFB server: {:?}",
            ep.addr,
            String::from_utf8_lossy(&ver)
        ));
    }
    tx(&mut s, b"RFB 003.008\n")?;
    let n = rx(&mut s, 1)?[0] as usize;
    if n == 0 {
        let len = be32(&rx(&mut s, 4)?) as usize;
        let why = rx(&mut s, len.min(4096))?;
        return Err(format!("console refused: {}", String::from_utf8_lossy(&why)));
    }
    let types = rx(&mut s, n)?;
    // A console that offers "None" alongside VNC Authentication is not the
    // one this harness configured; only the authenticated type is accepted.
    if !types.contains(&2) {
        return Err(format!(
            "console {} does not offer VNC Authentication (offers {types:?}); refusing to drive it",
            ep.addr
        ));
    }
    tx(&mut s, &[2])?;
    let mut ch = [0u8; 16];
    ch.copy_from_slice(&rx(&mut s, 16)?);
    tx(&mut s, &crate::des::vnc_response(ep.password.as_bytes(), &ch))?;
    if be32(&rx(&mut s, 4)?) != 0 {
        return Err(format!("console {} rejected the password", ep.addr));
    }
    tx(&mut s, &[1])?; // shared: another viewer stays connected
    let init = rx(&mut s, 24)?;
    let width = u16::from_be_bytes([init[0], init[1]]);
    let height = u16::from_be_bytes([init[2], init[3]]);
    let bpp = init[4];
    let name_len = be32(&init[20..24]) as usize;
    let name = String::from_utf8_lossy(&rx(&mut s, name_len.min(4096))?).to_string();
    if !matches!(bpp, 8 | 16 | 32) {
        return Err(format!("console reports {bpp} bits per pixel, which RFB does not define"));
    }
    Ok(Session { sock: s, width, height, bpp, name })
}

/// Read the whole screen once.
pub fn look(ep: &Endpoint, timeout: Duration) -> Result<Frame, String> {
    let mut s = open(ep, timeout)?;
    // SetEncodings: Raw only, so every rectangle is plain pixels.
    tx(&mut s.sock, &[2, 0, 0, 1, 0, 0, 0, 0])?;
    let mut req = vec![3u8, 0, 0, 0, 0, 0];
    req.extend_from_slice(&s.width.to_be_bytes());
    req.extend_from_slice(&s.height.to_be_bytes());
    tx(&mut s.sock, &req)?;
    let mut digest: u64 = 0xcbf2_9ce4_8422_2325;
    let mut covered: u64 = 0;
    let want = s.width as u64 * s.height as u64;
    let px = s.bpp as usize / 8;
    while covered < want {
        let t = rx(&mut s.sock, 1)?[0];
        match t {
            0 => {
                let hdr = rx(&mut s.sock, 3)?;
                let rects = u16::from_be_bytes([hdr[1], hdr[2]]);
                for _ in 0..rects {
                    let r = rx(&mut s.sock, 12)?;
                    let (x, y) = (u16::from_be_bytes([r[0], r[1]]), u16::from_be_bytes([r[2], r[3]]));
                    let (w, h) = (u16::from_be_bytes([r[4], r[5]]), u16::from_be_bytes([r[6], r[7]]));
                    let enc = i32::from_be_bytes([r[8], r[9], r[10], r[11]]);
                    if enc != 0 {
                        return Err(format!("console sent encoding {enc} after Raw was the only one asked for"));
                    }
                    for b in [x, y, w, h].iter().flat_map(|v| v.to_be_bytes()) {
                        digest = (digest ^ b as u64).wrapping_mul(0x100_0000_01b3);
                    }
                    let mut left = w as usize * h as usize * px;
                    let mut buf = vec![0u8; 65536];
                    while left > 0 {
                        let n = left.min(buf.len());
                        s.sock
                            .read_exact(&mut buf[..n])
                            .map_err(|e| format!("console read: {e}"))?;
                        for &b in &buf[..n] {
                            digest = (digest ^ b as u64).wrapping_mul(0x100_0000_01b3);
                        }
                        left -= n;
                    }
                    covered += w as u64 * h as u64;
                }
            }
            // Bell carries no payload; anything else is not ours to skip.
            2 => {}
            other => return Err(format!("console sent message type {other} during a screen read")),
        }
    }
    Ok(Frame { width: s.width, height: s.height, name: s.name, digest })
}

/// Press and release one key. Returns the desktop name the key went to.
pub fn press(ep: &Endpoint, keysym: u32, timeout: Duration) -> Result<String, String> {
    let mut s = open(ep, timeout)?;
    for down in [1u8, 0] {
        let mut ev = vec![4u8, down, 0, 0];
        ev.extend_from_slice(&keysym.to_be_bytes());
        tx(&mut s.sock, &ev)?;
    }
    Ok(s.name)
}
