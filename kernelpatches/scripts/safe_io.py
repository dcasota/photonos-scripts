"""
Input validation and safe filesystem helpers.

Every path this tool writes is built from three kinds of input:

* an operator-chosen base directory (``--output``, ``--repo-base``),
* a kernel series (``--kernel``/``--kernels``) or a full kernel version that
  was read from a spec file or from kernel.org,
* a file name (``--specs``, patch names, tar members).

The base directory is the operator's choice by contract. Everything that is
appended to it must not be able to leave it, so the helpers here validate
the appended parts strictly, confine the result to the base, and extract
archives without letting a member land outside the destination.
"""

import os
import re
import tarfile
from pathlib import Path
from typing import Callable, Optional, Union

from scripts.config import KERNEL_MAPPINGS

PathLike = Union[str, "os.PathLike[str]"]

# A full kernel version as published on kernel.org and in Photon spec files:
# "6.12", "5.10.247", "6.1.158". Only digits and dots, so it is safe both as
# a file name component and as a URL path component.
_VERSION_RE = re.compile(r"^[0-9]{1,4}(?:\.[0-9]{1,6}){1,3}$")

# A single file name: no separators, no NUL, not "." or "..".
_FILENAME_RE = re.compile(r"^[A-Za-z0-9._+-]{1,255}$")


def require_supported_kernel(kernel_version: str) -> str:
    """Return the canonical kernel series for ``kernel_version``.

    Raises ValueError when the series is not one of KERNEL_MAPPINGS. The
    value returned is the constant stored in the mapping, not the caller's
    string, so nothing user-supplied flows past this point.
    """
    wanted = str(kernel_version).strip()
    for supported_version in KERNEL_MAPPINGS:
        if supported_version == wanted:
            return supported_version
    supported = ", ".join(KERNEL_MAPPINGS)
    raise ValueError(
        f"Unsupported kernel version: {kernel_version!r} (supported: {supported})"
    )


def require_version(version: str, what: str = "kernel version") -> str:
    """Return ``version`` if it is a dotted numeric version, else raise ValueError."""
    if not isinstance(version, str) or not _VERSION_RE.fullmatch(version):
        raise ValueError(f"Invalid {what}: {version!r}")
    return version


def require_filename(name: str, what: str = "file name") -> str:
    """Return ``name`` if it is a single plain file name, else raise ValueError."""
    if (
        not isinstance(name, str)
        or not _FILENAME_RE.fullmatch(name)
        or name in (".", "..")
    ):
        raise ValueError(f"Invalid {what}: {name!r}")
    return name


def _is_within(root: str, candidate: str) -> bool:
    return candidate == root or candidate.startswith(root + os.sep)


def confine(base: PathLike, *parts: str) -> Path:
    """Join ``parts`` onto ``base`` and return the result.

    The joined path is resolved (symlinks included) and must stay inside the
    resolved ``base``; otherwise ValueError is raised.
    """
    root = os.path.realpath(os.fspath(base))
    candidate = os.path.realpath(os.path.join(root, *parts))
    if not _is_within(root, candidate):
        raise ValueError(f"Path {os.path.join(*parts)!r} escapes {root!r}")
    return Path(candidate)


def resolve_dir(path: PathLike, what: str = "directory") -> Path:
    """Return the absolute, symlink-resolved form of an operator-chosen directory.

    Raises ValueError when the path exists and is not a directory.
    """
    resolved = Path(os.path.realpath(os.path.expanduser(os.fspath(path))))
    if resolved.exists() and not resolved.is_dir():
        raise ValueError(f"{what} is not a directory: {resolved}")
    return resolved


# Python 3.12+, and 3.8.17+/3.9.17+/3.10.12+/3.11.4+, ship extraction filters.
_HAS_TAR_FILTER = hasattr(tarfile, "data_filter")


def _check_member(member: tarfile.TarInfo, root: str) -> None:
    """Reject a member whose name or link target leaves ``root``.

    This is a lexical check run before anything is written. The "data"
    extraction filter repeats the check against the filesystem as each
    member is extracted; on interpreters without filters this is the only
    check, so links are held to the same rule.
    """
    name = member.name
    if not name or "\x00" in name or os.path.isabs(name):
        raise tarfile.TarError(f"Unsafe tar member name: {name!r}")
    target = os.path.normpath(os.path.join(root, name))
    if not _is_within(root, target):
        raise tarfile.TarError(f"Tar member escapes destination: {name!r}")

    if member.ischr() or member.isblk() or member.isfifo():
        raise tarfile.TarError(f"Refusing special-file tar member: {name!r}")

    if member.issym() or member.islnk():
        link = member.linkname
        if not link or "\x00" in link or os.path.isabs(link):
            raise tarfile.TarError(f"Unsafe link target in tar member {name!r}: {link!r}")
        if member.issym():
            link_target = os.path.join(os.path.dirname(target), link)
        else:
            link_target = os.path.join(root, link)
        if not _is_within(root, os.path.normpath(link_target)):
            raise tarfile.TarError(f"Tar link escapes destination: {name!r} -> {link!r}")


def safe_extract_tar(
    tar: tarfile.TarFile,
    dest: PathLike,
    progress: Optional[Callable[[int, int], None]] = None,
) -> Path:
    """Extract every member of ``tar`` into ``dest`` without writing outside it.

    Each member's name and link target is checked before extraction. Where the
    interpreter supports it, extraction also uses the "data" filter, which
    re-checks every path against the filesystem as it is written, so a
    symlink planted by an earlier member cannot redirect a later one.

    Args:
        tar: An open TarFile.
        dest: Destination directory (created if missing).
        progress: Optional callback(done, total), called after each member.

    Returns:
        The resolved destination directory.

    Raises:
        tarfile.TarError: if any member is unsafe. Nothing is extracted when
        the pre-check fails.
    """
    os.makedirs(os.fspath(dest), exist_ok=True)
    root = os.path.realpath(os.fspath(dest))

    members = tar.getmembers()
    for member in members:
        _check_member(member, root)

    total = len(members)
    if progress is None:
        if _HAS_TAR_FILTER:
            tar.extractall(root, members=members, filter="data")
        else:
            tar.extractall(root, members=members)
    else:
        for done, member in enumerate(members, 1):
            if _HAS_TAR_FILTER:
                tar.extract(member, root, filter="data")
            else:
                tar.extract(member, root)
            progress(done, total)
    return Path(root)
