# Copyright 2011 MaestroDev
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class archiva($version, $user = "archiva", $group = "archiva", 
  $manage_user = true, $service = "archiva", $installroot = "/usr/local", 
  $home = "/var/local/archiva", 
  $apache_mirror = "http://archive.apache.org/dist/", 
  $repo = {
    #url = "http://repo1.maven.org/maven2",
    #username = "",
    #password = "",
  },
  $port = "8080", $application_url = "http://localhost:8080/archiva/",
  $mail_from = {
    #name => "Apache Archiva",
    #address => "archiva@example.com",
  },
  $ldap = {
    #hostname => "",
    #ssl => true,
    #port => "636",
    #dn => "",
    #bind_dn => "",
    #bind_password => "",
    #admin_user => "root",
  }, 
  $archiva_jdbc = {
    url => "jdbc:derby:/var/local/archiva/data/databases/archiva;create=true",
    driver => "org.apache.derby.jdbc.EmbeddedDriver",
    username => "sa",
    password => "",
  },
  $users_jdbc = {
    url => "jdbc:derby:/var/local/archiva/data/databases/users;create=true",
    driver => "org.apache.derby.jdbc.EmbeddedDriver",
    username => "sa",
    password => "",
  },
  $jdbc_driver_url = "",
  $maxmemory = undef,
  $jetty_version = undef,
  $forwarded = false) {

  # wget from https://github.com/maestrodev/puppet-wget
  include wget

  if $jetty_version == {
    if $version =~ /(1.[23].*|1.4-M1.*)/ {
      $jetty_version_real = 6
    } else {
      $jetty_version_real = 7
    }
  }
  else {
    $jetty_version_real = $jetty_version
  }

  File { owner => $user, group => $group, mode => "0644" }
  Exec { path => "/bin" }

  $installdir = "$installroot/apache-archiva-$version"
  $archive = "/usr/local/src/apache-archiva-${version}-bin.tar.gz"

  # Derby specifics
  if $archiva_jdbc['driver'] == "org.apache.derby.jdbc.EmbeddedDriver" {
    $archiva_u = regsubst($archiva_jdbc['url'],";.*$", "")
    $archiva_jdbc['shutdown_url'] = "$archiva_u;shutdown=true"
  }

  if $users_jdbc['driver'] == "org.apache.derby.jdbc.EmbeddedDriver" {
    $users_u = regsubst($users_jdbc['url'],";.*$", "")
    $users_jdbc['shutdown_url'] = "$users_u;shutdown=true"
  }

  if $manage_user {
    if $::puppetversion >= "2.7.0" {
      user { "$user":
        ensure     => present,
        home       => "$home",
        managehome => false,
        system     => true,
      }
    } else {
      user { "$user":
        ensure     => present,
        home       => "$home",
        managehome => false,
      }
    }

    group { "$group":
      ensure  => present,
      require => User["$user"],
    }
  }
  if "x${repo['url']}x" != "xx" {
    if "x${repo['username']}x" != "xx" {
      wget::authfetch { "archiva_download":
        source => "${repo['url']}/org/apache/archiva/archiva-jetty/$version/archiva-jetty-${version}-bin.tar.gz",
        destination => $archive,
        user => $repo['username'],
        password => $repo['password'],
        notify => Exec["archiva_untar"],
      }
    } else {
      wget::fetch { "archiva_download":
        source => "${repo['url']}/org/apache/archiva/archiva-jetty/$version/archiva-jetty-${version}-bin.tar.gz",
        destination => $archive,
        notify => Exec["archiva_untar"],
      }
    }
  } else {
    wget::fetch { "archiva_download":
      source => "$apache_mirror/archiva/binaries/apache-archiva-${version}-bin.tar.gz",
      destination => $archive,
      notify => Exec["archiva_untar"],
    }
  }
  exec { "archiva_untar":
    command => "tar zxf $archive",
    cwd     => "$installroot",
    creates => "$installdir",
    notify  => Service[$service],
  } ->
  file { "$installroot/$service":
    ensure  => link,
    target  => "$installdir",
  }
  if $::architecture == "x86_64" {
    file { "$installdir/bin/wrapper-linux-x86-32":
      ensure => absent,
      require => Exec["archiva_untar"],
    }
    file { "$installdir/lib/libwrapper-linux-x86-32.so":
      ensure => absent,
      require => Exec["archiva_untar"],
    }
  }
  if $jdbc_driver_url != "" {
    $filename = regsubst("$jdbc_driver_url","^.*/", "")
    wget::fetch { "archiva_jdbc_driver_download":
      source => "$jdbc_driver_url",
      destination => "$installdir/lib/$filename",
      require => Exec["archiva_untar"],
    } ->
    file { "${home}/conf/wrapper.conf":
      ensure  => link,
      target  => "${installdir}/conf/wrapper.conf",
    } ->
    exec { "archiva_jdbc_driver_append":
      command => "sed -i 's#=%REPO_DIR%/derby.*$#=%REPO_DIR%/$filename#' $home/conf/wrapper.conf",
      unless => "grep '=%REPO_DIR%/$filename' $home/conf/wrapper.conf",
      notify => Service[$service],
      require => [File["$home/conf"],Exec["archiva_untar"]],
    }
  } else {
    file { "${home}/conf/wrapper.conf":
      ensure  => link,
      target  => "${installdir}/conf/wrapper.conf",
    }
  }
  if $version == "1.4-M2" {
    exec { "fix_tmpdir_14M2":
      command => "sed -i 's#java.io.tmpdir=./temp#java.io.tmpdir=%ARCHIVA_BASE%/tmp#' $home/conf/wrapper.conf",
      unless => "grep 'java.io.tmpdir=%ARCHIVA_BASE%/tmp' $home/conf/wrapper.conf",
      notify => Service[$service],
      require => File["$home/conf/wrapper.conf"],
    }
  }
  file { "$home":
    ensure => directory,
  } ->
  file { "$home/temp":
    ensure => directory,
  } ->
  file { "$home/tmp":
    ensure => directory,
  } ->
  file { "$home/logs":
    ensure => directory,
  } ->
  file { "$home/conf":
    ensure => directory,
    require => Exec["archiva_untar"],
  } ->
  file { "$home/conf/shared.xml": ensure  => present, source => "$installdir/conf/shared.xml", } ->
  file { "$home/conf/jetty.xml": 
    ensure  => present,
    content => template("archiva/jetty$jetty_version_real.xml.erb"),
    notify  => Service[$service],
  } ->
  file { "$home/conf/security.properties": 
    ensure  => present,
    content => template("archiva/security.properties.erb"),
    notify  => Service[$service],
  } ->
  file { "/etc/profile.d/archiva.sh":
    owner   => "root",
    mode    => "0755",
    content => "export ARCHIVA_BASE=$home\n",
  } ->
  file { "/etc/init.d/$service":
    owner   => "root",
    mode    => "0755",
    content => template("archiva/archiva.erb"),
  } ->
  service { $service:
    ensure => running,
    hasrestart => true,
    hasstatus => true,
    enable => true,
  }

  if $maxmemory != undef {
    # Until Augeas has the properties files fixes, use a custom version
    # Just a basic approach - for more complete management of lenses consider https://github.com/camptocamp/puppet-augeas
    file { "/tmp/augeas": ensure => directory }
    file { "/tmp/augeas/archiva": ensure => directory } ->
    wget::fetch { "fetch-augeas-archiva":
      source => "https://raw.github.com/maestrodev/augeas/af585c7e29560306f23938b3ba15aa1104951f7f/lenses/properties.aug",
      destination => "/tmp/augeas/archiva/properties.aug",
    } ->

    # Adjust wrapper.conf
    augeas { "update-archiva-wrapper-config":
      lens => "Properties.lns",
      incl => "$home/conf/wrapper.conf",
      changes => "set wrapper.java.maxmemory $maxmemory",
      load_path => "/tmp/augeas/archiva",
      require => File["${home}/conf/wrapper.conf"],
    }
  }

}
