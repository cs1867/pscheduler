#
# RPM Spec for pScheduler PostgreSQL Archiver
#

%define short	postgresql
%define perfsonar_auto_version 5.0.0
%define perfsonar_auto_relnum 0.b2.8

Name:		pscheduler-archiver-%{short}
Version:	%{perfsonar_auto_version}
Release:	%{perfsonar_auto_relnum}%{?dist}

Summary:	PostgreSQL archiver for pScheduler
BuildArch:	noarch
License:	Apache 2.0
Group:		Unspecified

Source0:	%{short}-%{version}.tar.gz

Provides:	%{name} = %{version}-%{release}

Requires:	pscheduler-server >= 1.0.2
Requires:	%{_pscheduler_python_epel}-psycopg2 >= 2.6.1

BuildRequires:	pscheduler-rpm


%define directory %{_includedir}/make

%description
PostgreSQL archiver for pScheduler


%prep
%setup -q -n %{short}-%{version}


%define dest %{_pscheduler_archiver_libexec}/%{short}

%build
make \
     DESTDIR=$RPM_BUILD_ROOT/%{dest} \
     DOCDIR=$RPM_BUILD_ROOT/%{_pscheduler_archiver_doc} \
     install

%post
pscheduler internal warmboot

%postun
pscheduler internal warmboot

%files
%defattr(-,root,root,-)
%{dest}
%{_pscheduler_archiver_doc}/*