#
# RPM Spec for pScheduler __PLUGIN_NAME__ Archiver
#

%define short	__PLUGIN_NAME__
%define perfsonar_auto_version 5.1.3
%define perfsonar_auto_relnum 0.a1.0

Name:		pscheduler-archiver-%{short}
Version:	%{perfsonar_auto_version}
Release:	%{perfsonar_auto_relnum}%{?dist}

Summary:	__PLUGIN_NAME__ archiver class for pScheduler
BuildArch:	noarch
License:	Apache 2.0
Group:		Unspecified

Source0:	%{short}-%{version}.tar.gz

Provides:	%{name} = %{version}-%{release}

Requires:	pscheduler-server >= 1.0.2
Requires:	rpm-post-wrapper

BuildRequires:	pscheduler-rpm


%define directory %{_includedir}/make

%description
__PLUGIN_NAME__ archiver class for pScheduler


%prep
%setup -q -n %{short}-%{version}


%define dest %{_pscheduler_archiver_libexec}/%{short}

%build
make \
     DESTDIR=$RPM_BUILD_ROOT/%{dest} \
     DOCDIR=$RPM_BUILD_ROOT/%{_pscheduler_archiver_doc} \
     install

%post
rpm-post-wrapper '%{name}' "$@" <<'POST-WRAPPER-EOF'
pscheduler internal warmboot
POST-WRAPPER-EOF

%postun
pscheduler internal warmboot

%files
%defattr(-,root,root,-)
%{dest}
%{_pscheduler_archiver_doc}/*
