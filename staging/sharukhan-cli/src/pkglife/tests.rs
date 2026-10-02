//! Orchestration tests against a scripted guest. Every scenario that makes the
//! run skip, fail or stop is driven here with the guest's real output shapes,
//! and each has a negative control where "nothing happened" could pass.

use super::*;
use crate::pkglife::remote::fake::{self, Fake};

const BASE_QA: &str = "bash\t(none)\t5.3-1.ph5\tx86_64\nrpm\t(none)\t6.1.0-3.ph5\tx86_64\n";
const ACTIVE: &str = r#"[{"unit":"sshd.service"},{"unit":"systemd-journald.service"}]"#;

fn base() -> BTreeMap<String, Pkg> {
    parse::rpm_qa(BASE_QA).unwrap()
}

fn session<'a>(r: &'a mut Fake, p: &'a Policy) -> Session<'a> {
    Session {
        r,
        policy: p,
        nonce: "abc".into(),
        seq: 0,
        baseline: base(),
        failed_baseline: BTreeSet::new(),
        active_baseline: ["sshd.service", "systemd-journald.service"]
            .iter()
            .map(|s| s.to_string())
            .collect(),
        protected_active: ["sshd.service".to_string()].into_iter().collect(),
        boot_errors: Vec::new(),
        cli_disabled: None,
        lost: None,
        declared_conflicts: BTreeSet::new(),
    }
}

fn pkg(name: &str) -> Pkg {
    Pkg {
        name: name.into(),
        arch: "x86_64".into(),
        evr: "1.2.3-1.ph5".into(),
        repo: REPO_ID.into(),
    }
}

fn rec(name: &str) -> PkgRecord {
    PkgRecord {
        package: name.into(),
        evr: "1.2.3-1.ph5".into(),
        ..Default::default()
    }
}

const TOOL_FILES: &str = "/usr/bin/tool\t100755\t\t\n/usr/share/doc/tool/README\t100644\td\t\n";
const TOOL_INSTALL: &str =
    r#"{"Install":[{"Name":"tool","Arch":"x86_64","Evr":"1.2.3-1.ph5","Repo":"sharukhan-media"}]}"#;
const TOOL_REMOVE: &str =
    r#"{"Remove":[{"Name":"tool","Arch":"x86_64","Evr":"1.2.3-1.ph5","Repo":"@System"}]}"#;

/// A guest on which `tool` installs, works and removes cleanly.
fn healthy_tool() -> Fake {
    let mut f = Fake::new();
    f.on("'rpm' '-qp'", fake::ok(TOOL_FILES))
        .on("'--assumeno' 'install'", fake::ok(TOOL_INSTALL))
        .on("--show-cursor", fake::ok("-- cursor: s=1;i=1\n"))
        .on("'-y' 'install'", fake::ok(TOOL_INSTALL))
        .once(
            "'rpm' '-qa'",
            fake::ok(&format!("{BASE_QA}tool\t(none)\t1.2.3-1.ph5\tx86_64\n")),
        )
        .on("'rpm' '-qa'", fake::ok(BASE_QA))
        .on("'rpm' '-q' '--qf'", fake::ok(TOOL_FILES))
        .on("'rpm' '-V'", fake::ok(""))
        .on("'test' '-x'", fake::ok(""))
        .on("systemd-run", fake::ok("tool 1.2.3\n"))
        .on("journalctl", fake::ok(""))
        .on("'--assumeno' 'remove'", fake::ok(TOOL_REMOVE))
        .on("'-y' 'remove'", fake::ok(TOOL_REMOVE))
        .on("while IFS=", fake::ok(""))
        .on("readlink", fake::ok("1 /usr/lib/systemd/systemd\n"))
        .on("'--failed'", fake::ok("[]"))
        .on("'--state=active'", fake::ok(ACTIVE));
    f
}

fn status_of<'a>(r: &'a PkgRecord, step: &str) -> &'a str {
    r.steps
        .iter()
        .find(|s| s.name == step)
        .map(|s| s.status.as_str())
        .unwrap_or("absent")
}

#[test]
fn a_healthy_cli_package_goes_round_trip_and_passes() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    assert!(matches!(s.fresh(&pkg("tool"), &mut r), Flow::Continue));
    r.settle();
    assert_eq!(r.verdict, PASS, "{:#?}", r.steps);
    for step in [
        "resolve",
        "install",
        "rpm-verify",
        "journal-window",
        "remove",
        "files-gone",
        "processes-gone",
        "failed-units",
        "baseline-units",
    ] {
        assert_eq!(status_of(&r, step), PASS, "{step}: {:#?}", r.steps);
    }
    assert_eq!(r.clis.len(), 1);
    assert_eq!(r.clis[0].status, PASS);
    assert_eq!(r.classes, vec!["cli"]);
    assert_eq!(r.installed, vec!["tool-1.2.3-1.ph5.x86_64"]);
    assert_eq!(r.origin, "fresh");
    // the package name reached the guest quoted, after --
    assert_eq!(f.ran("'install' '--' 'tool'"), 2);
}

#[test]
fn a_transaction_touching_installed_packages_is_never_run() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'--assumeno' 'install'");
    f.on(
        "'--assumeno' 'install'",
        fake::ok(r#"{"Install":[{"Name":"tool","Arch":"x86_64","Evr":"1-1","Repo":"sharukhan-media"}],"Remove":[{"Name":"bash","Arch":"x86_64","Evr":"5.3-1.ph5","Repo":"@System"}]}"#),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    assert!(matches!(s.fresh(&pkg("tool"), &mut r), Flow::Continue));
    r.settle();
    assert_eq!(r.verdict, SKIP);
    assert!(r.reason.contains("Remove: bash"), "{}", r.reason);
    assert_eq!(f.ran("'-y' 'install'"), 0, "the install must not run");
}

#[test]
fn a_boot_affecting_package_is_skipped_before_resolution() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'rpm' '-qp'");
    f.on(
        "'rpm' '-qp'",
        fake::ok("/boot/vmlinuz-6.12\t100644\t\t\n/lib/modules/6.12/x.ko\t100644\t\t\n"),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("linux-x");
    s.fresh(&pkg("linux-x"), &mut r);
    r.settle();
    assert_eq!(r.verdict, SKIP);
    assert!(
        r.reason.starts_with("boot-affecting: installs 2"),
        "{}",
        r.reason
    );
    assert_eq!(f.ran("tdnf"), 0);
}

#[test]
fn unresolvable_dependencies_are_a_package_failure() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'--assumeno' 'install'");
    f.on(
        "'--assumeno' 'install'",
        fake::rc(
            1,
            r#"{"Error":1011,"ErrorMessage":"Solv general runtime error"}"#,
            "nothing provides libfoo.so.1",
        ),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    r.settle();
    assert_eq!(r.verdict, FAIL);
    assert_eq!(status_of(&r, "resolve"), FAIL);
    assert!(
        r.steps[0].detail.contains("nothing provides libfoo"),
        "{:?}",
        r.steps
    );
}

#[test]
fn a_package_from_another_repository_is_refused() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'--assumeno' 'install'");
    f.on(
        "'--assumeno' 'install'",
        fake::ok(
            r#"{"Install":[{"Name":"tool","Arch":"x86_64","Evr":"1-1","Repo":"photon-updates"}]}"#,
        ),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    assert_eq!(status_of(&r, "resolve"), FAIL);
    assert_eq!(f.ran("'-y' 'install'"), 0);
}

#[test]
fn an_install_that_removes_a_baseline_package_stops_the_run() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'rpm' '-qa'");
    f.on(
        "'rpm' '-qa'",
        fake::ok("rpm\t(none)\t6.1.0-3.ph5\tx86_64\ntool\t(none)\t1.2.3-1.ph5\tx86_64\n"),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    match s.fresh(&pkg("tool"), &mut r) {
        Flow::Abort(why) => assert!(why.contains("removed baseline package(s): bash"), "{why}"),
        Flow::Continue => panic!("a poisoned baseline must stop the run"),
    }
}

#[test]
fn files_left_behind_fail_the_package_but_kept_config_does_not() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules
        .retain(|r| r.needle != "while IFS=" && r.needle != "'rpm' '-q' '--qf'");
    f.on(
        "'rpm' '-q' '--qf'",
        fake::ok("/usr/bin/tool\t100755\t\t\n/etc/tool.conf\t100644\tcn\t\n"),
    )
    .on("while IFS=", fake::ok("/etc/tool.conf\n/usr/bin/tool\n"));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    r.settle();
    assert_eq!(status_of(&r, "files-gone"), FAIL);
    let d = &r
        .steps
        .iter()
        .find(|s| s.name == "files-gone")
        .unwrap()
        .detail;
    assert_eq!(d, "left behind: /usr/bin/tool");
    assert_eq!(r.verdict, FAIL);

    // negative control: only the %config file remains -> pass, recorded
    let mut f = healthy_tool();
    f.rules
        .retain(|r| r.needle != "while IFS=" && r.needle != "'rpm' '-q' '--qf'");
    f.on(
        "'rpm' '-q' '--qf'",
        fake::ok("/usr/bin/tool\t100755\t\t\n/etc/tool.conf\t100644\tcn\t\n"),
    )
    .on("while IFS=", fake::ok("/etc/tool.conf\n"));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    assert_eq!(status_of(&r, "files-gone"), PASS);
    assert!(r
        .steps
        .iter()
        .any(|s| s.detail.contains("kept %config: /etc/tool.conf")));
}

#[test]
fn a_process_still_running_a_removed_binary_fails() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "readlink");
    f.on(
        "readlink",
        fake::ok("1 /usr/lib/systemd/systemd\n4242 /usr/bin/tool (deleted)\n"),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    assert_eq!(status_of(&r, "processes-gone"), FAIL);
    assert!(r.steps.iter().any(|s| s.detail.contains("pid 4242")));
}

#[test]
fn a_removal_that_would_take_more_than_was_added_stops_the_run() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'--assumeno' 'remove'");
    f.on(
        "'--assumeno' 'remove'",
        fake::ok(r#"{"Remove":[{"Name":"tool","Arch":"x86_64","Evr":"1.2.3-1.ph5"},{"Name":"bash","Arch":"x86_64","Evr":"5.3-1.ph5"}]}"#),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    assert!(matches!(s.fresh(&pkg("tool"), &mut r), Flow::Abort(_)));
    assert_eq!(f.ran("'-y' 'remove'"), 0, "the removal must not run");
}

#[test]
fn a_failed_tdnf_removal_falls_back_to_rpm_for_exactly_what_was_added() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules
        .retain(|r| r.needle != "'rpm' '-qa'" && r.needle != "'-y' 'remove'");
    let with = format!("{BASE_QA}tool\t(none)\t1.2.3-1.ph5\tx86_64\n");
    f.once("'rpm' '-qa'", fake::ok(&with)) // after install
        .once("'rpm' '-qa'", fake::ok(&with)) // after the failed tdnf remove
        .on("'rpm' '-qa'", fake::ok(BASE_QA)) // after rpm -e
        .on("'-y' 'remove'", fake::rc(1, "", "scriptlet failed"))
        .on("'rpm' '-e' '--' 'tool'", fake::ok(""));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    assert!(matches!(s.fresh(&pkg("tool"), &mut r), Flow::Continue));
    assert_eq!(status_of(&r, "remove"), FAIL);
    assert_eq!(f.ran("'rpm' '-e' '--' 'tool'"), 1);
    assert_eq!(
        f.ran("--noscripts"),
        0,
        "scriptlets first; no forced removal was needed"
    );
}

#[test]
fn a_baseline_unit_the_package_stopped_is_restarted_and_reported() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'--state=active'");
    f.once("'--state=active'", fake::ok(r#"[{"unit":"sshd.service"}]"#))
        .on("'--state=active'", fake::ok(ACTIVE))
        .on("'systemctl' 'start'", fake::ok(""));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    assert!(matches!(s.fresh(&pkg("tool"), &mut r), Flow::Continue));
    assert_eq!(status_of(&r, "baseline-units"), FAIL);
    assert!(r.steps.iter().any(|s| s.detail.contains("restarted: all")));
    assert_eq!(
        f.ran("'systemctl' 'start' '--' 'systemd-journald.service'"),
        1
    );

    // ...and one that cannot be restarted stops the run
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'--state=active'");
    f.on("'--state=active'", fake::ok(r#"[{"unit":"sshd.service"}]"#))
        .on("'systemctl' 'start'", fake::rc(1, "", "failed"));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    assert!(matches!(s.fresh(&pkg("tool"), &mut r), Flow::Abort(_)));
}

#[test]
fn a_new_failed_unit_fails_the_package_and_is_cleared_for_the_next() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'--failed'");
    f.on(
        "'--failed'",
        fake::ok(r#"[{"unit":"tool-helper.service"}]"#),
    )
    .on("'reset-failed'", fake::ok(""));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    assert_eq!(status_of(&r, "failed-units"), FAIL);
    assert_eq!(f.ran("'reset-failed' '--' 'tool-helper.service'"), 1);
}

#[test]
fn journal_errors_in_the_window_fail_the_package_but_the_harness_own_do_not() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "journalctl");
    f.on(
        "journalctl",
        fake::ok(concat!(
            r#"{"_SYSTEMD_UNIT":"sharukhan-probe-abc-1.service","PRIORITY":"3","MESSAGE":"probe noise"}"#,
            "\n",
            r#"{"_SYSTEMD_UNIT":"dbus.service","PRIORITY":"3","MESSAGE":"tool broke dbus"}"#,
            "\n"
        )),
    );
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    assert_eq!(status_of(&r, "journal-window"), FAIL);
    assert_eq!(r.journal_errors.len(), 1);
    assert!(r.journal_errors[0].contains("tool broke dbus"));
}

#[test]
fn a_daemon_package_plans_every_unit_it_ships() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    let files = "/usr/lib/systemd/system/getty-x@.service\t100644\t\t\n/usr/lib/systemd/system/watchdog.service\t100644\t\t\n/usr/lib/systemd/system/x.mount\t100644\t\t\n";
    f.rules
        .retain(|r| r.needle != "'rpm' '-qp'" && r.needle != "'rpm' '-q' '--qf'");
    // systemctl refuses to show a template (measured: sshd@.service); the
    // plan must not need it
    f.rules.insert(
        0,
        fake::Rule {
            needle: "'--' 'getty-x@.service'".into(),
            out: fake::rc(
                1,
                "",
                "Failed to get properties: Unit name getty-x@.service is neither a valid invocation ID nor unit name.",
            ),
            times: None,
        },
    );
    f.on("'rpm' '-qp'", fake::ok(files))
        .on("'rpm' '-q' '--qf'", fake::ok(files))
        .on(
            "'systemctl' 'show'",
            fake::ok("LoadState=loaded\nNeedDaemonReload=yes\n"),
        )
        .on("daemon-reload", fake::ok(""));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    let plans: Vec<(&str, &str)> = r
        .units
        .iter()
        .map(|u| (u.unit.as_str(), u.status.as_str()))
        .collect();
    assert_eq!(
        plans,
        vec![
            ("getty-x@.service", SKIP),
            ("watchdog.service", SKIP),
            ("x.mount", SKIP)
        ]
    );
    assert!(r.units[1].plan.contains("reboots the guest"));
    // the stale systemd view was recorded and reloaded, once
    assert_eq!(status_of(&r, "daemon-reload"), INFO);
    assert!(f.ran("'systemctl' 'start'") == 0);
    // units-gone: the fake still says loaded -> reload -> still loaded -> fail
    assert_eq!(status_of(&r, "units-gone"), FAIL);
}

#[test]
fn preinstalled_packages_are_tested_in_place_and_never_removed() {
    let p = Policy::embedded().unwrap();
    let mut f = Fake::new();
    f.on("--show-cursor", fake::ok("-- cursor: s=1;i=1\n"))
        .on("'rpm' '-V'", fake::ok("S.5....T.  c /etc/fstab\n"))
        .on(
            "'rpm' '-q' '--qf'",
            fake::ok("/usr/bin/rpm\t100755\t\t\n/usr/lib/systemd/system/rpmdb-migrate.service\t100644\t\t\n/usr/lib/librpm.so.10\t120777\t\tlibrpm.so.10.0.0\n"),
        )
        .on("ldconfig -p", fake::ok("\tlibrpm.so.10 (libc6,x86-64) => /usr/lib/librpm.so.10\n"))
        .on("'test' '-x'", fake::ok(""))
        .on("systemd-run", fake::ok("RPM version 6.1.0\n"))
        .on("'systemctl' 'show'", fake::ok("LoadState=loaded\nActiveState=inactive\nSubState=dead\nUnitFileState=disabled\n"))
        .on("journalctl", fake::ok(""));
    let mut s = session(&mut f, &p);
    let mut r = rec("rpm");
    s.preinstalled("rpm", &mut r);
    r.settle();
    assert_eq!(r.verdict, PASS, "{:#?}", r);
    assert_eq!(r.origin, "preinstalled");
    assert_eq!(r.classes, vec!["daemon", "cli", "library"]);
    assert_eq!(status_of(&r, "rpm-verify"), PASS);
    assert_eq!(status_of(&r, "ldcache"), PASS);
    assert_eq!(r.units[0].outcome, "observed");
    assert_eq!(f.ran("tdnf"), 0);
    assert_eq!(
        f.ran("'systemctl' 'start'") + f.ran("'systemctl' 'stop'"),
        0
    );
}

#[test]
fn cli_probes_are_skipped_with_the_reason_when_their_controls_failed() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    let mut s = session(&mut f, &p);
    s.cli_disabled = Some("sandbox not in force".into());
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    assert!(r.clis.is_empty());
    assert!(r
        .steps
        .iter()
        .any(|x| x.name == "cli" && x.status == SKIP && x.detail.contains("sandbox")));
    assert_eq!(f.ran("systemd-run"), 0);
}

#[test]
fn a_dangling_executable_is_a_cli_failure() {
    let p = Policy::embedded().unwrap();
    let mut f = healthy_tool();
    f.rules.retain(|r| r.needle != "'test' '-x'");
    f.on("'test' '-x'", fake::rc(1, "", ""));
    let mut s = session(&mut f, &p);
    let mut r = rec("tool");
    s.fresh(&pkg("tool"), &mut r);
    assert_eq!(r.clis[0].status, FAIL);
    assert!(r.clis[0].reason.contains("not executable"));
}

// ---- controls ------------------------------------------------------------

#[test]
fn the_journal_control_needs_its_own_line_back() {
    let p = Policy::embedded().unwrap();
    let mut f = Fake::new();
    f.on("--show-cursor", fake::ok("-- cursor: s=1;i=1\n"))
        .on("'logger'", fake::ok(""))
        .on(
            "journalctl",
            fake::ok(r#"{"SYSLOG_IDENTIFIER":"sharukhan-control","PRIORITY":"3","MESSAGE":"journal control abc"}"#),
        );
    let mut s = session(&mut f, &p);
    assert!(s.control_journal().is_ok());
    let mut f = Fake::new();
    f.on("--show-cursor", fake::ok("-- cursor: s=1;i=1\n"))
        .on("'logger'", fake::ok(""))
        .on("journalctl", fake::ok(""));
    let mut s = session(&mut f, &p);
    let t = Instant::now();
    assert!(s
        .control_journal()
        .unwrap_err()
        .contains("did not return it"));
    assert!(
        t.elapsed().as_secs() >= 10,
        "the poll is bounded, not skipped"
    );
}

#[test]
fn the_unit_control_must_be_judged_failed_with_its_line_found() {
    let p = Policy::embedded().unwrap();
    let mut f = Fake::new();
    f.on("--show-cursor", fake::ok("-- cursor: s=1;i=1\n"))
        .on("systemd-run", fake::rc(3, "", ""))
        .on("'systemctl' 'show'", fake::ok("LoadState=loaded\nActiveState=failed\nResult=exit-code\n"))
        .on(
            "journalctl",
            fake::ok(r#"{"_SYSTEMD_UNIT":"sharukhan-control-abc.service","PRIORITY":"3","MESSAGE":"unit control abc"}"#),
        )
        .on("reset-failed", fake::ok(""));
    let mut s = session(&mut f, &p);
    assert!(s.control_unit().unwrap().contains("found"));
    // negative control: a unit judged up means the judgement is broken
    let mut g = Fake::new();
    g.on("--show-cursor", fake::ok("-- cursor: s=1;i=1\n"))
        .on("systemd-run", fake::rc(3, "", ""))
        .on(
            "'systemctl' 'show'",
            fake::ok("LoadState=loaded\nActiveState=active\nSubState=running\nResult=success\n"),
        )
        .on("journalctl", fake::ok(""))
        .on("reset-failed", fake::ok(""));
    let mut s = session(&mut g, &p);
    assert!(s.control_unit().unwrap_err().contains("judged Up"));
}

#[test]
fn the_cli_control_proves_sandbox_good_and_bad() {
    let p = Policy::embedded().unwrap();
    let mut f = Fake::new();
    f.on("'/bin/sh' '-c'", fake::ok("61234\nlo \nread-only\n"))
        .on("'/usr/bin/rpm'", fake::ok("RPM version 6.1.0\n"))
        .on(
            "'/usr/bin/false'",
            fake::rc(1, "false (GNU coreutils) 9.1\n", ""),
        );
    let mut s = session(&mut f, &p);
    let m = s.control_cli().unwrap();
    assert!(m.contains("uid 61234"), "{m}");
    // a `false` that passes means the judgement is vacuous
    let mut g = Fake::new();
    g.on("'/bin/sh' '-c'", fake::ok("61234\nlo \nread-only\n"))
        .on("'/usr/bin/rpm'", fake::ok("RPM version 6.1.0\n"))
        .on("'/usr/bin/false'", fake::ok("false 9.1\n"));
    let mut s = session(&mut g, &p);
    assert!(s.control_cli().unwrap_err().contains("known-bad"));
    // no sandbox, no probes
    let mut h = Fake::new();
    h.on("'/bin/sh' '-c'", fake::ok("0\nlo eth0 \nwritable\n"));
    let mut s = session(&mut h, &p);
    assert!(s
        .control_cli()
        .unwrap_err()
        .contains("sandbox not in force"));
}

// ---- pure rules -------------------------------------------------------------

#[test]
fn rpm_verify_rule() {
    let lines = parse::rpm_verify(
        "S.5....T.  c /etc/fstab\n.M.......    /proc\nmissing     /run/media/cdrom\n\
         SM5...GT.    /var/log/wtmp\n.M.......  g /sys\n..5......    /usr/bin/tool\n\
         missing     /usr/lib/libx.so.1\n.....U...    /usr/bin/other\nUnsatisfied dependencies for x:\n",
    );
    let (fails, infos) = judge_verify(&lines);
    assert_eq!(
        fails,
        vec![
            "..5...... ' ' /usr/bin/tool".replace("' '", " "),
            "missing   /usr/lib/libx.so.1".to_string(),
            "Unsatisfied dependencies for x:".to_string()
        ]
    );
    // config, runtime trees and metadata-only differences are recorded
    assert_eq!(infos.len(), 5, "{infos:?}");
}

#[test]
fn window_and_session_noise_rules() {
    let e = parse::journal_json(concat!(
        r#"{"_SYSTEMD_UNIT":"x.service","PRIORITY":"2","MESSAGE":"crit"}"#,
        "\n",
        r#"{"_SYSTEMD_UNIT":"x.service","PRIORITY":"4","MESSAGE":"warn"}"#,
        "\n",
        r#"{"SYSLOG_IDENTIFIER":"sharukhan-control","PRIORITY":"3","MESSAGE":"ctl"}"#,
        "\n"
    ))
    .unwrap();
    assert_eq!(window_errors(&e).len(), 1);
    assert!(session_noise("user@0.service"));
    assert!(session_noise("session-12.scope"));
    assert!(session_noise("sharukhan-probe-1.service"));
    assert!(!session_noise("sshd.service"));
}

#[test]
fn leftover_processes_match_exact_paths_only() {
    let files: BTreeSet<String> = ["/usr/sbin/x".to_string()].into_iter().collect();
    let procs = vec![
        (1, "/usr/lib/systemd/systemd".to_string()),
        (5, "/usr/sbin/x (deleted)".to_string()),
        (6, "/usr/sbin/xy".to_string()),
    ];
    assert_eq!(
        leftover_processes(&procs, &files),
        vec!["pid 5 /usr/sbin/x (deleted)"]
    );
}

#[test]
fn linker_cache_rule() {
    let c = classify::classify(
        &parse::rpm_files(
            "/usr/lib/libz.so.1\t120777\t\tlibz.so.1.3\n/usr/lib/libz.so.1.3\t100755\t\t\n",
        )
        .unwrap(),
        |_| false,
    );
    let mut cache = BTreeSet::new();
    let (missing, _) = judge_ldcache(&c, &cache);
    assert_eq!(missing, vec!["/usr/lib/libz.so.1"]);
    cache.insert("/usr/lib/libz.so.1".to_string());
    assert!(judge_ldcache(&c, &cache).0.is_empty());
    // no conventional soname: one cached object is enough, none is a failure
    let py = classify::classify(
        &parse::rpm_files("/usr/lib/libpython3.14.so.1.0\t100755\t\t\n").unwrap(),
        |_| false,
    );
    assert_eq!(judge_ldcache(&py, &BTreeSet::new()).0.len(), 1);
    let mut c2 = BTreeSet::new();
    c2.insert("/usr/lib/libpython3.14.so.1.0".to_string());
    assert!(judge_ldcache(&py, &c2).0.is_empty());
}

#[test]
fn candidates_are_sorted_filtered_limited_and_resumed() {
    let a = vec![pkg("zeta"), pkg("alpha"), pkg("mid"), {
        let mut p = pkg("alpha");
        p.evr = "1.10-1.ph5".into();
        p
    }];
    let none = BTreeSet::new();
    let all = candidates(&a, None, None, &none).unwrap();
    assert_eq!(
        all.iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
        vec!["alpha", "mid", "zeta"]
    );
    assert_eq!(all[0].evr, "1.10-1.ph5", "the newest build of a name");
    let only = vec!["zeta".to_string(), "mid".to_string()];
    let v = candidates(&a, Some(&only), Some(1), &none).unwrap();
    assert_eq!(
        v.iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
        vec!["mid"]
    );
    let mut done = BTreeSet::new();
    done.insert("alpha".to_string());
    assert_eq!(candidates(&a, None, None, &done).unwrap().len(), 2);
    let e = candidates(&a, Some(&["nope".to_string()]), None, &none).unwrap_err();
    assert!(e.contains("not on the media: nope"));
}

#[test]
fn evr_ordering() {
    assert!(rpm_newer("1.10-1", "1.9-1"));
    assert!(!rpm_newer("1.9-1", "1.10-1"));
    assert!(rpm_newer("1:1.0-1", "2.0-1"));
    assert!(rpm_newer("1.0-2.ph5", "1.0-1.ph5"));
    assert!(!rpm_newer("1.0-1.ph5", "1.0-1.ph5"));
    assert!(rpm_newer("1.0.1-1", "1.0-1"));
    assert!(rpm_newer("1.0a-1", "1.0-1"));
    assert!(rpm_newer("2-1", "1a-1"));
    assert!(
        rpm_newer("1.0a-1", "1.0-2"),
        "version decides before release"
    );
    assert!(!rpm_newer("1.0-2", "1.0a-1"));
}

#[test]
fn package_options_are_validated() {
    assert_eq!(
        Opts::parse_packages("a, b ,c").unwrap(),
        vec!["a", "b", "c"]
    );
    assert!(Opts::parse_packages(",,").is_err());
    assert!(Opts::parse_packages("ok,-rf").is_err());
    assert!(Opts::parse_packages("a;reboot").is_err());
}

#[test]
fn the_password_never_reaches_a_record() {
    let mut r = rec("x");
    r.reason = "pw=hunter22".into();
    r.steps.push(Step::new("a", FAIL, "saw hunter22", 0));
    r.units.push(record::UnitResult {
        outcome: "hunter22".into(),
        journal_errors: vec!["hunter22".into()],
        steps: vec![Step::new("b", FAIL, "hunter22", 0)],
        ..Default::default()
    });
    r.clis.push(record::CliResult {
        reason: "hunter22".into(),
        attempts: vec![record::ProbeAttempt {
            stdout: "hunter22".into(),
            stderr: "hunter22".into(),
            verdict: "hunter22".into(),
            ..Default::default()
        }],
        ..Default::default()
    });
    r.journal_errors.push("hunter22".into());
    scrub_record(&mut r, Some("hunter22"));
    let text = serde_json::to_string(&r).unwrap();
    assert!(!text.contains("hunter22"), "{text}");
    assert!(text.contains(crate::phases::REDACTED));
    // negative control: without a secret nothing is rewritten
    let mut r2 = rec("x");
    r2.reason = "hunter22".into();
    scrub_record(&mut r2, None);
    assert_eq!(r2.reason, "hunter22");
}

#[test]
fn tallies() {
    let mut s = Summary::default();
    for v in [PASS, FAIL, SKIP, NOT_REACHED, PASS] {
        tally(&mut s, v);
    }
    assert_eq!((s.pass, s.fail, s.skip, s.not_reached), (2, 1, 1, 1));
}

#[test]
fn the_harvest_comparison_speaks_plain_rpm_qa() {
    // captured on k09: gpg-pubkey has neither arch nor epoch
    let now = parse::rpm_qa(
        "bash\t(none)\t5.3-1.ph5\tx86_64\ngpg-pubkey\t(none)\t66fd4949-4803fe57\t(none)\nperl\t4\t5.40-1.ph5\tx86_64\n",
    )
    .unwrap();
    let harvest = "bash-5.3-1.ph5.x86_64\ngpg-pubkey-66fd4949-4803fe57\nperl-5.40-1.ph5.x86_64\n";
    assert!(harvest_matches(harvest, &now).is_ok());
    let e = harvest_matches("bash-5.3-1.ph5.x86_64\nzsh-1-1.x86_64\n", &now).unwrap_err();
    assert!(
        e.contains("only in the harvest: [\"zsh-1-1.x86_64\"]"),
        "{e}"
    );
    assert!(e.contains("gpg-pubkey-66fd4949-4803fe57"), "{e}");
}

#[test]
fn a_declared_conflict_is_restored_and_recorded_not_failed() {
    let p = Policy::embedded().unwrap();
    let mut f = Fake::new();
    f.once("'--state=active'", fake::ok(r#"[{"unit":"sshd.service"}]"#))
        .on("'--state=active'", fake::ok(ACTIVE))
        .on("'systemctl' 'start'", fake::ok(""))
        .on("readlink", fake::ok(""))
        .on("'--failed'", fake::ok("[]"));
    let mut s = session(&mut f, &p);
    s.declared_conflicts
        .insert("systemd-journald.service".into());
    let mut r = rec("nft-like");
    assert!(matches!(
        s.residue(&[], &BTreeSet::new(), &BTreeSet::new(), &mut r),
        Flow::Continue
    ));
    assert_eq!(status_of(&r, "baseline-units"), INFO, "{:?}", r.steps);
    assert!(r
        .steps
        .iter()
        .any(|x| x.detail.contains("declared Conflicts=")));
}

// ---- the whole run, against a guest that behaves like the k09 one ---------

const REPO: &str = r#"[{"Name":"tool","Arch":"x86_64","Evr":"1.2.3-1.ph5","Repo":"sharukhan-media"},{"Name":"rpm","Arch":"x86_64","Evr":"6.1.0-3.ph5","Repo":"sharukhan-media"},{"Name":"bash","Arch":"x86_64","Evr":"5.3-1.ph5","Repo":"sharukhan-media"}]"#;

fn media_files() -> BTreeSet<String> {
    [
        "tool-1.2.3-1.ph5.x86_64.rpm",
        "rpm-6.1.0-3.ph5.x86_64.rpm",
        "bash-5.3-1.ph5.x86_64.rpm",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

/// A guest for a complete run: controls, baseline, one fresh CLI package.
fn whole_guest() -> Fake {
    let mut f = Fake::new();
    f.journal = Some(Vec::new());
    let with_tool = format!("{BASE_QA}tool\t(none)\t1.2.3-1.ph5\tx86_64\n");
    f.on("'repoquery'", fake::ok(REPO))
        .once("'rpm' '-qa'", fake::ok(BASE_QA)) // baseline
        .once("'rpm' '-qa'", fake::ok(&with_tool)) // after install
        .on("'rpm' '-qa'", fake::ok(BASE_QA))
        .on(
            "'list-unit-files'",
            fake::ok(r#"[{"unit_file":"sshd.service","state":"enabled"}]"#),
        )
        .on("'--failed'", fake::ok("[]"))
        .on("'--state=active'", fake::ok(ACTIVE))
        .on(
            "ss -Hltnp",
            fake::ok("LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=7,fd=3))\n"),
        )
        .on(
            "/proc/7/cgroup",
            fake::ok("0::/system.slice/sshd.service\n"),
        )
        .on("'journalctl' '-b'", fake::ok(""))
        .on("--show-cursor", fake::ok("-- cursor: s=1;i=1\n"))
        .on(
            "'-p' 'Id,",
            fake::ok("LoadState=loaded\nActiveState=failed\nResult=exit-code\n"),
        )
        .on("reset-failed", fake::ok(""))
        .on("'/bin/sh' '-c'", fake::ok("65534\nlo \nread-only\n"))
        .on(
            "'/usr/bin/false'",
            fake::rc(1, "false (GNU coreutils) 9.1\n", ""),
        )
        .on(
            "'/usr/bin/rpm' '--version'",
            fake::ok("RPM version 6.1.0\n"),
        )
        .on("'rpm' '-qp'", fake::ok(TOOL_FILES))
        .on("'--assumeno' 'install'", fake::ok(TOOL_INSTALL))
        .on("'-y' 'install'", fake::ok(TOOL_INSTALL))
        .on("'rpm' '-q' '--qf'", fake::ok(TOOL_FILES))
        .on("'rpm' '-V'", fake::ok(""))
        .on("'test' '-x'", fake::ok(""))
        .on("systemd-run", fake::ok("tool 1.2.3\n"))
        .on("'--assumeno' 'remove'", fake::ok(TOOL_REMOVE))
        .on("'-y' 'remove'", fake::ok(TOOL_REMOVE))
        .on("while IFS=", fake::ok(""))
        .on("readlink", fake::ok("1 /usr/lib/systemd/systemd\n"));
    f
}

struct World {
    dir: std::path::PathBuf,
    cfg: Config,
    perm: Permutation,
}

fn world(tag: &str) -> World {
    use std::str::FromStr;
    let dir = std::env::temp_dir().join(format!("sharukhan-run-{}-{tag}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("k09")).unwrap();
    let mut cfg = Config::for_test(&dir);
    cfg.results_dir = dir.clone();
    let perm = Permutation {
        id: "k09".into(),
        iso_type: "full".into(),
        poi: "2.8".into(),
        stig: "no".into(),
        fs: "ext4".into(),
        mode: "ks".into(),
        variant: "none".into(),
        doc: "untested".into(),
        expect: "pass".into(),
        canister: "prebuilt".into(),
        net: crate::net::NetSpec::from_str(crate::net::DEFAULT).unwrap(),
    };
    World { dir, cfg, perm }
}

const MID: &str = "fd2cbd06b8574dafb91d6de0bdfac4c1";

fn go(
    w: &World,
    f: &mut Fake,
    o: &Opts,
    stamp: &str,
    files: &BTreeSet<String>,
) -> (Result<Summary, String>, String) {
    let p = Policy::embedded().unwrap();
    let t = Target {
        cfg: &w.cfg,
        perm: &w.perm,
        iso: Path::new("/nonexistent.iso"),
        ip: "10.0.0.1",
        stamp,
    };
    let mut c = Checks::init(&w.dir, "k09", stamp).unwrap();
    c.echo = false;
    let mut log = |_: &str| {};
    let r = run_attached(
        &t,
        f,
        &p,
        &mut c,
        o,
        &mut log,
        MID,
        Some("hunter22"),
        Instant::now(),
        files,
    );
    let text = std::fs::read_to_string(&c.path).unwrap();
    (r, text)
}

fn opts(pkgs: &[&str]) -> Opts {
    Opts {
        packages: Some(pkgs.iter().map(|s| s.to_string()).collect()),
        budget_secs: 3600,
        ..Default::default()
    }
}

fn check_status(checks: &str, id: &str) -> String {
    checks
        .lines()
        .filter_map(|l| serde_json::from_str::<serde_json::Value>(l).ok())
        .find(|v| v["check"] == id)
        .map(|v| v["status"].as_str().unwrap_or("").to_string())
        .unwrap_or_else(|| "absent".into())
}

#[test]
fn a_whole_run_proves_its_controls_tests_and_restores_the_baseline() {
    let w = world("whole");
    let mut f = whole_guest();
    let (r, checks) = go(&w, &mut f, &opts(&["tool", "rpm"]), "s1", &media_files());
    let s = r.unwrap();
    assert_eq!((s.pass, s.fail, s.not_reached), (2, 0, 0), "{checks}");
    assert!(checks.contains("no verify harvest of this run to compare with"));
    for (id, want) in [
        ("pkg.repo_is_media", "pass"),
        ("pkg.baseline", "info"),
        ("pkg.ssh_unit", "info"),
        ("pkg.control.journal", "pass"),
        ("pkg.control.unit_failure", "pass"),
        ("pkg.control.cli", "pass"),
        ("pkg.life.tool", "pass"),
        ("pkg.baseline_restored", "pass"),
        ("pkg.summary", "info"),
    ] {
        assert_eq!(check_status(&checks, id), want, "{id}\n{checks}");
    }
    // rpm is preinstalled: tested in place, never removed
    assert!(f.ran("'remove' '--' 'rpm'") == 0);
    // the baseline file and the records exist, the records carry no secret
    assert!(w
        .dir
        .join(format!("k09/pkglife-baseline-{MID}.txt"))
        .is_file());
    let recs = record::read(&w.dir.join("k09/pkglife-s1.jsonl")).unwrap();
    assert_eq!(recs.len(), 2);
    assert_eq!(recs[1].package, "tool");
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_resumed_run_on_the_same_guest_carries_final_verdicts_and_retests_nothing() {
    let w = world("resume");
    let mut f = whole_guest();
    go(&w, &mut f, &opts(&["tool"]), "s1", &media_files())
        .0
        .unwrap();
    let mut g = whole_guest();
    let mut o = opts(&["tool"]);
    o.resume = true;
    let (r, checks) = go(&w, &mut g, &o, "s2", &media_files());
    let s = r.unwrap();
    assert_eq!((s.carried, s.pass), (1, 1));
    assert_eq!(
        g.ran("'-y' 'install'"),
        0,
        "a carried package is not re-tested"
    );
    assert_eq!(check_status(&checks, "pkg.baseline"), "pass", "{checks}");
    let recs = record::read(&w.dir.join("k09/pkglife-s2.jsonl")).unwrap();
    assert_eq!(recs[0].carried_from.as_deref(), Some("pkglife-s1.jsonl"));
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn leftovers_of_an_interrupted_run_are_removed_before_anything_else() {
    let w = world("leftover");
    std::fs::write(
        w.dir.join(format!("k09/pkglife-baseline-{MID}.txt")),
        "bash-5.3-1.ph5.x86_64\nrpm-6.1.0-3.ph5.x86_64\n",
    )
    .unwrap();
    let mut f = whole_guest();
    f.rules.retain(|r| r.needle != "'rpm' '-qa'");
    f.once(
        "'rpm' '-qa'",
        fake::ok(&format!("{BASE_QA}tool\t(none)\t1.2.3-1.ph5\tx86_64\n")),
    )
    .on("'rpm' '-qa'", fake::ok(BASE_QA));
    let (r, checks) = go(&w, &mut f, &opts(&["rpm"]), "s1", &media_files());
    r.unwrap();
    assert_eq!(check_status(&checks, "pkg.baseline"), "info");
    assert!(
        checks.contains("left over by an interrupted run"),
        "{checks}"
    );
    assert_eq!(f.ran("'-y' 'remove' '--' 'tool'"), 1);
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_guest_that_lost_baseline_packages_is_refused() {
    let w = world("lost");
    std::fs::write(
        w.dir.join(format!("k09/pkglife-baseline-{MID}.txt")),
        "bash-5.3-1.ph5.x86_64\nrpm-6.1.0-3.ph5.x86_64\nvim-9-1.x86_64\n",
    )
    .unwrap();
    let mut f = whole_guest();
    let (r, checks) = go(&w, &mut f, &opts(&["tool"]), "s1", &media_files());
    assert!(r.unwrap_err().contains("lost 1 baseline package"));
    assert_eq!(check_status(&checks, "pkg.baseline"), "fail");
    assert_eq!(f.ran("install"), 0);
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_guest_that_is_not_the_one_verify_harvested_is_refused() {
    let w = world("harvest");
    let logs = w.dir.join("k09/logs-s1");
    std::fs::create_dir_all(&logs).unwrap();
    std::fs::write(logs.join("rpm-qa.txt"), "bash-5.3-1.ph5.x86_64\n").unwrap();
    let mut f = whole_guest();
    let (r, checks) = go(&w, &mut f, &opts(&["tool"]), "s1", &media_files());
    assert!(r
        .unwrap_err()
        .contains("only now: [\"rpm-6.1.0-3.ph5.x86_64\"]"));
    assert_eq!(check_status(&checks, "pkg.baseline"), "fail");
    // negative control: a matching harvest is accepted
    std::fs::write(
        logs.join("rpm-qa.txt"),
        "bash-5.3-1.ph5.x86_64\nrpm-6.1.0-3.ph5.x86_64\n",
    )
    .unwrap();
    let _ = std::fs::remove_file(w.dir.join(format!("k09/pkglife-baseline-{MID}.txt")));
    let mut g = whole_guest();
    let (r, checks) = go(&w, &mut g, &opts(&["tool"]), "s1", &media_files());
    assert!(r.is_ok());
    assert!(
        checks.contains("matches the verify harvest of this run"),
        "{checks}"
    );
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_repository_that_is_not_the_media_stops_the_run_before_any_install() {
    let w = world("repo");
    let mut f = whole_guest();
    let mut files = media_files();
    files.remove("tool-1.2.3-1.ph5.x86_64.rpm");
    let (r, checks) = go(&w, &mut f, &opts(&["tool"]), "s1", &files);
    assert!(r.is_err());
    assert_eq!(check_status(&checks, "pkg.repo_is_media"), "fail");
    assert_eq!(f.ran("'rpm' '-qa'"), 0);
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_spent_budget_records_the_rest_as_not_reached() {
    let w = world("budget");
    let mut f = whole_guest();
    let mut o = opts(&["tool", "rpm"]);
    o.budget_secs = 0;
    let (r, checks) = go(&w, &mut f, &o, "s1", &media_files());
    let s = r.unwrap();
    assert_eq!(s.not_reached, 2);
    assert!(s.aborted.unwrap().contains("budget"));
    assert!(checks.contains("2 not reached"), "{checks}");
    assert_eq!(f.ran("'-y' 'install'"), 0);
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_poisoned_guest_stops_the_loop_and_the_rest_is_not_reached() {
    let w = world("poison");
    let mut f = whole_guest();
    f.rules.retain(|r| r.needle != "'rpm' '-qa'");
    f.once("'rpm' '-qa'", fake::ok(BASE_QA))
        // the install took bash with it
        .on(
            "'rpm' '-qa'",
            fake::ok("rpm\t(none)\t6.1.0-3.ph5\tx86_64\ntool\t(none)\t1.2.3-1.ph5\tx86_64\n"),
        );
    let (r, checks) = go(&w, &mut f, &opts(&["tool", "bash"]), "s1", &media_files());
    let s = r.unwrap();
    // bash sorts first and is preinstalled; tool poisons; nothing after it
    assert_eq!(s.fail, 1, "{checks}");
    assert!(s.aborted.unwrap().contains("removed baseline package"));
    assert_eq!(check_status(&checks, "pkg.baseline_restored"), "fail");
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_failed_journal_control_stops_the_run() {
    let w = world("jctl");
    let mut f = whole_guest();
    f.journal = None;
    f.rules.insert(
        0,
        fake::Rule {
            needle: "'logger'".into(),
            out: fake::ok(""),
            times: None,
        },
    );
    f.rules.insert(
        0,
        fake::Rule {
            needle: "--after-cursor".into(),
            out: fake::ok(""),
            times: None,
        },
    );
    let (r, checks) = go(&w, &mut f, &opts(&["tool"]), "s1", &media_files());
    assert!(r.unwrap_err().contains("vacuous"));
    assert_eq!(check_status(&checks, "pkg.control.journal"), "fail");
    assert_eq!(f.ran("install"), 0);
    std::fs::remove_dir_all(&w.dir).ok();
}

#[test]
fn a_failed_cli_control_disables_probes_but_not_the_run() {
    let w = world("cli");
    let mut f = whole_guest();
    f.rules.retain(|r| r.needle != "'/bin/sh' '-c'");
    f.rules.insert(
        0,
        fake::Rule {
            needle: "'/bin/sh' '-c'".into(),
            out: fake::ok("0\nlo eth0 \nwritable\n"),
            times: None,
        },
    );
    let (r, checks) = go(&w, &mut f, &opts(&["tool"]), "s1", &media_files());
    r.unwrap();
    assert_eq!(check_status(&checks, "pkg.control.cli"), "fail");
    let recs = record::read(&w.dir.join("k09/pkglife-s1.jsonl")).unwrap();
    assert!(recs[0]
        .steps
        .iter()
        .any(|s| s.name == "cli" && s.status == SKIP));
    std::fs::remove_dir_all(&w.dir).ok();
}

fn failed(pkg: &str, steps: &[&str]) -> PkgRecord {
    let mut r = PkgRecord { package: pkg.into(), ..Default::default() };
    for st in steps {
        r.steps.push(Step::new(st, FAIL, "ssh: connect to host port 22: Connection timed out", 0));
    }
    r.settle();
    r
}

#[test]
fn a_reachable_guest_keeps_the_fail_and_the_run_going() {
    let mut r = failed("ivykis", &["header"]);
    assert_eq!(unreachable_after(&mut r, true, Some("itstool")), None);
    assert_eq!(r.verdict, FAIL);
}

#[test]
fn reads_that_fail_on_a_lost_guest_are_not_reached_and_blame_the_previous_package() {
    for steps in [&["header"][..], &["rpm-verify", "files"][..], &["resolve"][..]] {
        let mut r = failed("ivykis", steps);
        let why = unreachable_after(&mut r, false, Some("itstool")).expect("the run must stop");
        assert_eq!(why, "guest unreachable after testing itstool");
        assert_eq!(r.verdict, NOT_REACHED, "{steps:?}");
    }
}

#[test]
fn a_package_that_changed_the_guest_keeps_its_fail_when_the_guest_is_lost() {
    let mut r = failed("itstool", &["files-gone", "failed-units"]);
    let why = unreachable_after(&mut r, false, Some("isa-l-devel")).expect("the run must stop");
    assert_eq!(why, "guest unreachable after testing itstool");
    assert_eq!(r.verdict, FAIL);
    assert!(r.steps.iter().any(|s| s.name == "guest-state"));
}

#[test]
fn a_passing_package_never_stops_the_run() {
    let mut r = PkgRecord { package: "a".into(), verdict: PASS.into(), ..Default::default() };
    assert_eq!(unreachable_after(&mut r, false, None), None);
}
