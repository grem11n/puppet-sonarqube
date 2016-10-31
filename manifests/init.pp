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
class sonarqube (
  $version          = '4.5.5',
  $user             = 'sonar',
  $group            = 'sonar',
  $user_system      = true,
  $service          = 'sonar',
  $installroot      = '/usr/local',
  $home             = undef,
  $data_dir         = undef,
  $temp_dir         = undef,
  $host             = undef,
  $port             = 9000,
  $portajp          = -1,
  $download_url     = 'https://sonarsource.bintray.com/Distribution/sonarqube',
  $download_dir     = '/usr/local/src',
  $context_path     = '/',
  $arch             = $sonarqube::params::arch,
  $https            = {},
  $ldap             = {},
  # ldap and pam are mutually exclusive. Setting $ldap will annihilate the setting of $pam
  $pam              = {},
  $crowd            = {},
  $jdbc             = {
    url                               => 'jdbc:h2:tcp://localhost:9092/sonar',
    username                          => 'sonar',
    password                          => 'sonar',
    max_active                        => '50',
    max_idle                          => '5',
    min_idle                          => '2',
    max_wait                          => '5000',
    min_evictable_idle_time_millis    => '600000',
    time_between_eviction_runs_millis => '30000',
  },
  $log_folder       = undef,
  $updatecenter     = true,
  $http_proxy       = {},
  $profile          = false,
  $web_java_opts    = undef,
  $search_java_opts = undef,
  $search_host      = '127.0.0.1',
  $search_port      = '9001',
  $config           = undef,
  $path             = {
    data_dir        => undef,
    temp_dir        => undef,
  },
) inherits sonarqube::params {
  validate_absolute_path($download_dir)
  Exec {
    path => '/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin',
  }
  File {
    owner => $user,
    group => $group,
  }

  # wget from https://github.com/maestrodev/puppet-wget
  include wget

  $package_name = 'sonarqube'

  if $home != undef {
    $real_home = $home
  } else {
    $real_home = '/var/local/sonar'
  }

  if $path[data_dir] != undef {
    $real_data_dir = $path[data_dir]
  } else {
    $real_data_dir = "${real_home}/data"
  }

  if $log_folder != undef {
    $real_log_folder = $log_folder
  } else {
    $real_log_folder = '/var/local/sonar/logs'
  }

  Sonarqube::Move_to_home {
    home => $real_home,
  }

  $extensions_dir = "${real_home}/extensions"
  $plugin_dir = "${extensions_dir}/plugins"

  $installdir = "${installroot}/${service}"
  $tmpzip = "${download_dir}/${package_name}-${version}.zip"
  $script = "${installdir}/bin/${arch}/sonar.sh"

  if ! defined(Package[unzip]) {
    package { 'unzip':
      ensure => present,
      before => Exec[untar],
    }
  }

  user { $user:
    ensure     => present,
    home       => $real_home,
    managehome => false,
    system     => $user_system,
  }
  ->
  group { $group:
    ensure => present,
    system => $user_system,
  }
  ->
  wget::fetch { 'download-sonar':
    source      => "${download_url}/${package_name}-${version}.zip",
    destination => $tmpzip,
  }
  ->
  # ===== Create folder structure =====
  # so uncompressing new sonar versions at update time use the previous sonar home,
  # installing new extensions and plugins over the old ones, reusing the db,...

  # Sonar home
  file { $real_home:
    ensure => directory,
    mode   => '0700',
  }
  ->
  file { "${installroot}/${package_name}-${version}":
    ensure => directory,
  }
  ->
  file { $installdir:
    ensure => link,
    target => "${installroot}/${package_name}-${version}",
    notify => Service['sonarqube'],
  }
  if $path[data_dir] != undef {
    exec { 'create_data_dir':
      command => "mkdir -p ${real_data_dir}",
      creates => $real_data_dir,
      require => File[$real_home],
    }
    ->
    file { $real_data_dir:
      ensure => directory,
      owner  => $user,
      group  => $group,
    }
  }
  if $path[temp_dir] != undef {
    exec { 'create_temp_dir':
      command => "mkdir -p ${path[temp_dir]}",
      creates => $path[temp_dir],
      require => File[$real_home],
    }
    ->
    file { $path[temp_dir]:
      ensure => directory,
      owner  => $user,
      group  => $group,
    }
  }
  if $log_folder != undef {
    exec { 'create_log_folder':
      command => "mkdir -p ${real_log_folder}",
      creates => $real_log_folder,
      require => File[$real_home],
    }
    ->
    file { $real_log_folder:
      ensure => directory,
      owner  => $user,
      group  => $group,
    }
  }
  sonarqube::move_to_home { 'data':
    require => File[$real_home],
  }
  ->
  sonarqube::move_to_home { 'extras': }
  ->
  sonarqube::move_to_home { 'extensions': }
  ->
  sonarqube::move_to_home { 'logs': }
  ->
  # ===== Install SonarQube =====
  exec { 'untar':
    command => "unzip -o ${tmpzip} -d ${installroot} && chown -R \
      ${user}:${group} ${installroot}/${package_name}-${version} && chown -R ${user}:${group} ${real_home}",
    creates => "${installroot}/${package_name}-${version}/bin",
    notify  => Service['sonarqube'],
  }
  ->
  file { $script:
    mode    => '0755',
    content => template('sonarqube/sonar.sh.erb'),
  }
  ->
  file { "/etc/init.d/${service}":
    ensure => link,
    target => $script,
  }

  # Sonar configuration files
  if $config != undef {
    file { "${installdir}/conf/sonar.properties":
      source  => $config,
      require => Exec['untar'],
      notify  => Service['sonarqube'],
      mode    => '0600',
    }
  } else {
    file { "${installdir}/conf/sonar.properties":
      content => template('sonarqube/sonar.properties.erb'),
      require => Exec['untar'],
      notify  => Service['sonarqube'],
      mode    => '0600',
    }
  }

  file { '/tmp/cleanup-old-plugin-versions.sh':
    content => template("${module_name}/cleanup-old-plugin-versions.sh.erb"),
    mode    => '0755',
  }
  ->
  file { '/tmp/cleanup-old-sonarqube-versions.sh':
    content => template("${module_name}/cleanup-old-sonarqube-versions.sh.erb"),
    mode    => '0755',
  }
  ->
  exec { 'remove-old-versions-of-sonarqube':
    command     => "/tmp/cleanup-old-sonarqube-versions.sh ${installroot} ${version}",
    path        => '/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin',
    refreshonly => true,
    subscribe   => File["${installroot}/${package_name}-${version}"],
  }

  # The plugins directory. Useful to later reference it from the plugin definition
  file { $plugin_dir:
    ensure => directory,
  }

  service { 'sonarqube':
    ensure     => running,
    name       => $service,
    hasrestart => true,
    hasstatus  => true,
    enable     => true,
    require    => File["/etc/init.d/${service}"],
  }
}
