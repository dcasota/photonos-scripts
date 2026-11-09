"""Tests for scripts.safe_io: input validation and safe tar extraction."""

import io
import tarfile

import pytest

from scripts.safe_io import (
    confine,
    require_filename,
    require_supported_kernel,
    require_version,
    resolve_dir,
    safe_extract_tar,
)


def _make_tar(path, members):
    """members: list of (name, kind, payload) with kind in file/dir/sym/hard/fifo."""
    with tarfile.open(path, "w") as tar:
        for name, kind, payload in members:
            info = tarfile.TarInfo(name)
            if kind == "file":
                data = payload.encode()
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
                continue
            if kind == "dir":
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
            elif kind == "sym":
                info.type = tarfile.SYMTYPE
                info.linkname = payload
            elif kind == "hard":
                info.type = tarfile.LNKTYPE
                info.linkname = payload
            elif kind == "fifo":
                info.type = tarfile.FIFOTYPE
            tar.addfile(info)
    return path


class TestValidators:
    def test_supported_kernel_returns_canonical_value(self):
        assert require_supported_kernel("6.12") == "6.12"
        assert require_supported_kernel(" 5.10 ") == "5.10"

    @pytest.mark.parametrize("bad", ["", "7.0", "../6.12", "6.12/..", "all"])
    def test_unsupported_kernel_rejected(self, bad):
        with pytest.raises(ValueError):
            require_supported_kernel(bad)

    @pytest.mark.parametrize("good", ["6.12", "5.10.247", "6.1.158", "6.12.57"])
    def test_version_accepted(self, good):
        assert require_version(good) == good

    @pytest.mark.parametrize(
        "bad", ["", "6", "../../etc", "6.1/../x", "6.1.1\n", "6.1;rm", "6.1.x", None]
    )
    def test_version_rejected(self, bad):
        with pytest.raises(ValueError):
            require_version(bad)

    @pytest.mark.parametrize("good", ["linux-esx.spec", "0001-CVE-2024-1234.patch"])
    def test_filename_accepted(self, good):
        assert require_filename(good) == good

    @pytest.mark.parametrize("bad", ["", ".", "..", "a/b", "../x.spec", "/etc/passwd", "a\x00b"])
    def test_filename_rejected(self, bad):
        with pytest.raises(ValueError):
            require_filename(bad)


class TestConfine:
    def test_child_allowed(self, tmp_path):
        assert confine(tmp_path, "a", "b.txt") == tmp_path.resolve() / "a" / "b.txt"

    @pytest.mark.parametrize("parts", [("..",), ("../x",), ("a", "../../x"), ("/etc/passwd",)])
    def test_escape_rejected(self, tmp_path, parts):
        with pytest.raises(ValueError):
            confine(tmp_path, *parts)

    def test_symlink_escape_rejected(self, tmp_path):
        outside = tmp_path / "outside"
        base = tmp_path / "base"
        outside.mkdir()
        base.mkdir()
        (base / "link").symlink_to(outside)
        with pytest.raises(ValueError):
            confine(base, "link", "file")

    def test_resolve_dir_rejects_file(self, tmp_path):
        f = tmp_path / "f"
        f.write_text("x")
        with pytest.raises(ValueError):
            resolve_dir(f)
        assert resolve_dir(tmp_path) == tmp_path.resolve()


@pytest.fixture(params=[True, False], ids=["data-filter", "no-filter"], autouse=False)
def filter_mode(request, monkeypatch):
    """Run with the stdlib "data" filter and with the pre-3.12 fallback."""
    import scripts.safe_io as safe_io
    if request.param and not safe_io._HAS_TAR_FILTER:
        pytest.skip("interpreter has no tar extraction filters")
    monkeypatch.setattr(safe_io, "_HAS_TAR_FILTER", request.param)
    return request.param


@pytest.mark.usefixtures("filter_mode")
class TestSafeExtractTar:
    def test_normal_tree_with_internal_symlink(self, tmp_path):
        archive = _make_tar(tmp_path / "ok.tar", [
            ("linux-1.0", "dir", None),
            ("linux-1.0/Makefile", "file", "all:\n"),
            ("linux-1.0/include", "dir", None),
            ("linux-1.0/include/h.h", "file", "x"),
            ("linux-1.0/arch", "dir", None),
            ("linux-1.0/arch/inc", "sym", "../include"),
            ("linux-1.0/Makefile.hard", "hard", "linux-1.0/Makefile"),
        ])
        dest = tmp_path / "dest"
        with tarfile.open(archive) as tar:
            safe_extract_tar(tar, dest)
        assert (dest / "linux-1.0" / "Makefile").read_text() == "all:\n"
        assert (dest / "linux-1.0" / "arch" / "inc" / "h.h").read_text() == "x"

    def test_progress_callback(self, tmp_path):
        archive = _make_tar(tmp_path / "ok.tar", [("a", "file", "1"), ("b", "file", "2")])
        seen = []
        with tarfile.open(archive) as tar:
            safe_extract_tar(tar, tmp_path / "dest", progress=lambda d, t: seen.append((d, t)))
        assert seen == [(1, 2), (2, 2)]

    @pytest.mark.parametrize("members", [
        [("../evil", "file", "x")],
        [("/tmp/evil-abs", "file", "x")],
        [("a/../../evil", "file", "x")],
        # Symlink to outside, then a file written through it: the bypass the
        # old realpath-before-extractall guard let through.
        [("linux/escape", "sym", "{outside}"), ("linux/escape/pwned", "file", "x")],
        [("linux/escape", "sym", "../../outside"), ("linux/escape/pwned", "file", "x")],
        [("linux/hl", "hard", "../outside/target")],
        [("linux/fifo", "fifo", None)],
    ])
    def test_malicious_archives_rejected(self, tmp_path, members):
        outside = tmp_path / "outside"
        outside.mkdir()
        members = [
            (n, k, p.format(outside=outside) if isinstance(p, str) else p)
            for n, k, p in members
        ]
        archive = _make_tar(tmp_path / "evil.tar", members)
        dest = tmp_path / "dest"
        with tarfile.open(archive) as tar:
            with pytest.raises(tarfile.TarError):
                safe_extract_tar(tar, dest)
        assert list(outside.iterdir()) == []
        # The pre-check runs before anything is written.
        assert list(dest.iterdir()) == []
