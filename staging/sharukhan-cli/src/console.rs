//! Answering a boot menu that waits for a key, on an unattended row.
//!
//! A kickstart row must reach the installer with nobody at the console. That
//! holds for every medium whose menu boots its default entry on a timer, and
//! it does not hold for POI 2.8 media under BIOS: syslinux reads
//! `/isolinux/isolinux.cfg` from photon-iso-config, which says `timeout 0`,
//! so the menu waits for Enter for ever. b01 sat on it for the whole install
//! timeout with an empty serial log and no lease (gate 63, 2026-10-09).
//!
//! Whether a row needs this is read from the medium when the VM is created
//! ([`crate::isoboot::boot_menu`]); only then does the VMX get a console, and
//! the console is VMware's own VNC server, bound to the host's WSL-facing
//! address, on a port derived from the row's ordinal, with a password drawn
//! from the kernel's CSPRNG for that VM alone.
//!
//! The key is pressed on evidence, never on a timer: the screen must hold
//! the same picture for [`SETTLE`] (the VMware BIOS logo is the same size as
//! the vesamenu and lasts about three seconds, so size alone cannot tell them
//! apart), and after Enter the screen must leave that picture. If it does not,
//! Enter is pressed again, up to [`ATTEMPTS`] times; a menu that never
//! appears, or never goes, is reported as such and the install phase then
//! times out on its own evidence.

use crate::vnc::{self, Endpoint, Frame};
use std::net::{IpAddr, SocketAddr};
use std::time::{Duration, Instant};

/// How long one picture must hold before it is taken to be the menu.
pub const SETTLE: Duration = Duration::from_secs(6);
/// How often the screen is read.
const POLL: Duration = Duration::from_secs(1);
/// How long the menu may take to appear after power-on.
const APPEAR: Duration = Duration::from_secs(240);
/// How long the screen has to leave the menu after one Enter.
const LEAVE: Duration = Duration::from_secs(15);
/// How long the menu must stay gone once the screen has changed.
const CONFIRM: Duration = Duration::from_secs(10);
/// Presses before giving up on a menu that does not react.
pub const ATTEMPTS: u32 = 3;
/// First console port; the row's ordinal is added.
pub const PORT_BASE: u16 = 6000;
/// VNC Authentication truncates a password to 8 bytes.
const PASSWORD_LEN: usize = 8;
const IO: Duration = Duration::from_secs(5);

/// The VMX lines that give a VM its console, and what the harness needs to
/// reach it.
#[derive(Clone)]
pub struct Console {
    pub ip: IpAddr,
    pub port: u16,
    pub password: String,
}

impl Console {
    /// A console for the VM with matrix ordinal `index`.
    pub fn for_row(index: usize) -> Result<Self, String> {
        let port = u16::try_from(index)
            .ok()
            .and_then(|i| PORT_BASE.checked_add(i))
            .ok_or_else(|| format!("row ordinal {index} gives no console port"))?;
        let ip = wsl_host_address()?;
        if std::net::TcpStream::connect_timeout(&SocketAddr::new(ip, port), Duration::from_secs(1)).is_ok() {
            return Err(format!(
                "console port {ip}:{port} already answers before this VM exists; \
                 another VM or program holds it"
            ));
        }
        Ok(Console { ip, port, password: password()? })
    }

    pub fn vmx_lines(&self) -> String {
        format!(
            "RemoteDisplay.vnc.enabled = \"TRUE\"\n\
             RemoteDisplay.vnc.ip = \"{}\"\n\
             RemoteDisplay.vnc.port = \"{}\"\n\
             RemoteDisplay.vnc.password = \"{}\"",
            self.ip, self.port, self.password
        )
    }

    /// The console a rendered VMX declares, if it declares one.
    pub fn from_vmx(text: &str) -> Result<Option<Self>, String> {
        let get = |k: &str| {
            text.lines().find_map(|l| {
                let (a, b) = l.split_once('=')?;
                (a.trim().eq_ignore_ascii_case(k)).then(|| b.trim().trim_matches('"').to_string())
            })
        };
        if !get("RemoteDisplay.vnc.enabled").is_some_and(|v| v.eq_ignore_ascii_case("TRUE")) {
            return Ok(None);
        }
        let ip = get("RemoteDisplay.vnc.ip")
            .ok_or("the VMX enables a console without RemoteDisplay.vnc.ip")?
            .parse::<IpAddr>()
            .map_err(|e| format!("RemoteDisplay.vnc.ip: {e}"))?;
        let port = get("RemoteDisplay.vnc.port")
            .ok_or("the VMX enables a console without RemoteDisplay.vnc.port")?
            .parse::<u16>()
            .map_err(|e| format!("RemoteDisplay.vnc.port: {e}"))?;
        let password = get("RemoteDisplay.vnc.password")
            .filter(|p| !p.is_empty())
            .ok_or("the VMX enables a console without RemoteDisplay.vnc.password")?;
        Ok(Some(Console { ip, port, password }))
    }

    fn endpoint(&self) -> Endpoint {
        Endpoint { addr: SocketAddr::new(self.ip, self.port), password: self.password.clone() }
    }
}

/// The Windows host as WSL reaches it: the gateway of the default route.
/// That address lives on the Hyper-V internal switch, so a console bound to it
/// is reachable from this WSL instance and the host, not from the LAN or from
/// the guests on the VMware NAT network.
pub fn wsl_host_address() -> Result<IpAddr, String> {
    let text = std::fs::read_to_string("/proc/net/route").map_err(|e| format!("/proc/net/route: {e}"))?;
    default_gateway(&text).ok_or_else(|| "no IPv4 default route; the Windows host address is unknown".into())
}

/// The gateway of the first default route in a /proc/net/route table.
pub fn default_gateway(table: &str) -> Option<IpAddr> {
    table.lines().skip(1).find_map(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        if f.len() < 3 || f[1] != "00000000" {
            return None;
        }
        let g = u32::from_str_radix(f[2], 16).ok().filter(|g| *g != 0)?;
        Some(IpAddr::from(g.to_le_bytes()))
    })
}

/// An 8-character alphanumeric password from /dev/urandom, by rejection
/// sampling so every character is equally likely.
fn password() -> Result<String, String> {
    use std::io::Read;
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut f = std::fs::File::open("/dev/urandom").map_err(|e| format!("/dev/urandom: {e}"))?;
    let mut out = String::with_capacity(PASSWORD_LEN);
    let mut buf = [0u8; 64];
    while out.len() < PASSWORD_LEN {
        f.read_exact(&mut buf).map_err(|e| format!("/dev/urandom: {e}"))?;
        for b in buf {
            // 248 = 4 * 62: bytes above it would favour the first characters.
            if b < 248 && out.len() < PASSWORD_LEN {
                out.push(ALPHABET[(b % 62) as usize] as char);
            }
        }
    }
    Ok(out)
}

/// What answering the menu came to, for mc-facts.env and the oracle.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    /// The screen left the menu after `presses` Enter keys.
    Left { presses: u32, after: Duration },
    /// The menu never settled, or never went away.
    Stuck(String),
}

impl Outcome {
    pub fn fact(&self) -> String {
        match self {
            Outcome::Left { presses, after } => {
                format!("left|Enter x{presses}, the screen left the menu {}s after power-on", after.as_secs())
            }
            Outcome::Stuck(why) => format!("stuck|{why}"),
        }
    }
}

/// Decides from successive screens when the menu is up and when it has gone.
/// Kept apart from the network so the decision can be tested.
pub struct Watch {
    settle: Duration,
    held: Option<(Frame, Instant)>,
}

impl Watch {
    pub fn new(settle: Duration) -> Self {
        Watch { settle, held: None }
    }

    /// Feed one screen; returns the picture once it has held for `settle`.
    pub fn settled(&mut self, f: Frame, now: Instant) -> Option<Frame> {
        match &self.held {
            Some((h, since)) if *h == f => (now.duration_since(*since) >= self.settle).then(|| f),
            _ => {
                self.held = Some((f, now));
                None
            }
        }
    }
}

/// Answer the menu on the VM named `vm_name` through `console`.
pub fn leave_menu(console: &Console, vm_name: &str, started: Instant, log: &mut dyn FnMut(&str)) -> Outcome {
    let ep = console.endpoint();
    let mut watch = Watch::new(SETTLE);
    let mut last_err = String::new();
    let appear_by = Instant::now() + APPEAR;
    let mut presses = 0u32;
    loop {
        // 1. wait for a picture that holds
        let menu = loop {
            if Instant::now() > appear_by {
                return Outcome::Stuck(format!(
                    "no screen held still for {}s within {}s of power-on{}",
                    SETTLE.as_secs(),
                    APPEAR.as_secs(),
                    if last_err.is_empty() { String::new() } else { format!(" (last console error: {last_err})") }
                ));
            }
            match vnc::look(&ep, IO) {
                Ok(f) if f.name != vm_name => {
                    return Outcome::Stuck(format!(
                        "the console at {} belongs to '{}', not {vm_name}; no key was sent",
                        ep.addr, f.name
                    ))
                }
                Ok(f) => {
                    if let Some(m) = watch.settled(f, Instant::now()) {
                        break m;
                    }
                }
                Err(e) => last_err = e,
            }
            std::thread::sleep(POLL);
        };
        if presses >= ATTEMPTS {
            return Outcome::Stuck(format!(
                "the menu ({}x{}) stayed after {presses} Enter key(s)",
                menu.width, menu.height
            ));
        }
        // 2. press Enter on it
        match vnc::press(&ep, vnc::XK_RETURN, IO) {
            Ok(_) => presses += 1,
            Err(e) => return Outcome::Stuck(format!("Enter could not be sent: {e}")),
        }
        log(&format!(
            "boot menu: the {}x{} screen held {}s; pressed Enter ({presses}/{ATTEMPTS})",
            menu.width,
            menu.height,
            SETTLE.as_secs()
        ));
        // 3. the screen must leave that picture, and not come back to it:
        //    a menu that merely redrew would otherwise pass for one that booted
        let leave_by = Instant::now() + LEAVE;
        let mut left_at: Option<(Instant, Frame)> = None;
        while Instant::now() < leave_by || left_at.is_some() {
            std::thread::sleep(POLL);
            let f = match vnc::look(&ep, IO) {
                Ok(f) => f,
                Err(e) => {
                    last_err = e;
                    continue;
                }
            };
            match &left_at {
                None if f != menu => left_at = Some((Instant::now(), f)),
                None => {}
                Some(_) if f == menu => {
                    log("boot menu: the menu came back after the screen changed; not left");
                    left_at = None;
                    break;
                }
                Some((at, first)) if at.elapsed() >= CONFIRM => {
                    log(&format!(
                        "boot menu: left - the screen went to {}x{} and the menu has not returned for {}s",
                        first.width,
                        first.height,
                        CONFIRM.as_secs()
                    ));
                    return Outcome::Left { presses, after: started.elapsed() };
                }
                Some(_) => {}
            }
        }
        watch = Watch::new(SETTLE);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fr(w: u16, h: u16, d: u64) -> Frame {
        Frame { width: w, height: h, name: "mc-b01".into(), digest: d }
    }

    /// The sequence the probe VM showed: BIOS logo 640x480 for ~3s, loader
    /// text 720x400, then the vesamenu at 640x480. The logo must not pass for
    /// the menu, however alike their sizes.
    #[test]
    fn only_a_picture_that_holds_counts_as_the_menu() {
        let t0 = Instant::now();
        let s = |n: u64| t0 + Duration::from_secs(n);
        let mut w = Watch::new(SETTLE);
        assert_eq!(w.settled(fr(640, 480, 1), s(0)), None);
        assert_eq!(w.settled(fr(640, 480, 1), s(3)), None);
        assert_eq!(w.settled(fr(720, 400, 2), s(4)), None);
        assert_eq!(w.settled(fr(640, 480, 3), s(5)), None);
        assert_eq!(w.settled(fr(640, 480, 3), s(10)), None);
        assert_eq!(w.settled(fr(640, 480, 3), s(11)), Some(fr(640, 480, 3)));
    }

    #[test]
    fn a_change_restarts_the_clock() {
        let t0 = Instant::now();
        let mut w = Watch::new(SETTLE);
        w.settled(fr(640, 480, 3), t0);
        assert_eq!(w.settled(fr(640, 480, 4), t0 + Duration::from_secs(7)), None);
        assert!(w.settled(fr(640, 480, 4), t0 + Duration::from_secs(13)).is_some());
    }

    #[test]
    fn the_default_gateway_is_read_little_endian() {
        let t = "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n\
                 eth0\t00000000\t0140A8C0\t0003\t0\t0\t0\t00000000\t0\t0\t0\n\
                 eth0\t0040A8C0\t00000000\t0001\t0\t0\t0\t00F0FFFF\t0\t0\t0\n";
        assert_eq!(default_gateway(t), Some("192.168.64.1".parse().unwrap()));
        assert_eq!(default_gateway("Iface\tDestination\tGateway\neth0\t0040A8C0\t00000000\n"), None);
    }

    #[test]
    fn a_vmx_console_round_trips_and_a_partial_one_is_refused() {
        let c = Console { ip: "172.28.64.1".parse().unwrap(), port: 6044, password: "Ab3dEf7h".into() };
        let back = Console::from_vmx(&c.vmx_lines()).unwrap().unwrap();
        assert_eq!((back.ip, back.port, back.password.as_str()), (c.ip, c.port, "Ab3dEf7h"));
        assert!(Console::from_vmx("# no console\n").unwrap().is_none());
        assert!(Console::from_vmx("RemoteDisplay.vnc.enabled = \"TRUE\"\n").is_err());
    }

    /// Against a real VM: SHK_CONSOLE_VMX names a VMX (WSL path) that the
    /// caller has just powered on from a medium whose menu waits.
    /// `cargo test -- --ignored live_menu_is_left`
    #[test]
    #[ignore]
    fn live_menu_is_left() {
        let vmx = std::env::var("SHK_CONSOLE_VMX").expect("SHK_CONSOLE_VMX");
        let text = std::fs::read_to_string(&vmx).unwrap();
        let c = Console::from_vmx(&text).unwrap().expect("the VMX declares no console");
        let name = text
            .lines()
            .find_map(|l| l.strip_prefix("displayName = ").map(|v| v.trim_matches('"').to_string()))
            .unwrap();
        let mut log = |m: &str| eprintln!("{m}");
        let out = leave_menu(&c, &name, Instant::now(), &mut log);
        eprintln!("{}", out.fact());
        assert!(matches!(out, Outcome::Left { .. }), "{out:?}");
    }

    #[test]
    fn passwords_are_eight_alphanumerics_and_differ() {
        let a = password().unwrap();
        let b = password().unwrap();
        assert_eq!(a.len(), 8);
        assert!(a.bytes().all(|c| c.is_ascii_alphanumeric()));
        assert_ne!(a, b);
    }
}
