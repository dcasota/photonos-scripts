Name:           spagat-librarian
Version:        0.1.0
Release:        1%{?dist}
Summary:        Kanban Task Manager for Photon OS

License:        MIT
URL:            https://github.com/photon-os/spagat-librarian
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  sqlite-devel
BuildRequires:  ncurses-devel

Requires:       sqlite
Requires:       ncurses

%description
SPAGAT-Librarian is a CLI-based Kanban task manager written in C.
It provides both a text user interface (TUI) using ncurses and a
command-line interface for managing tasks through 6 workflow stages:
In Clarification, Won't Fix, In Backlog, In Progress, In Review, and Ready.

%prep
%setup -q

%build
make release %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}

%files
%{_bindir}/spagat-librarian
%doc PLAN.md MEANING.md

%changelog
* Sat Feb 14 2026 SPAGAT Team <spagat@photon.local> - 0.1.0-1
- Initial release
- Core kanban functionality with 6 status columns
- ncurses TUI with multi-select support
- SQLite database backend
- CLI commands for scripting
