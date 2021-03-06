# To use PostgreSQL, add the following recipes calls to your manifest:
#
#    recipe :postgresql_server, :postgresql_gem, :postgresql_user, :postgresql_database
#
module Moonshine::Manifest::Rails::Postgresql

  def postgresql_version
    ubuntu_lucid? ? '8.4' : '8.3'
  end

  # Installs <tt>postgresql</tt> from apt and enables the <tt>postgresql</tt>
  # service.
  def postgresql_server
    # pre-reqs for 9.x packages
    package 'python-software-properties', :ensure => :installed

    exec 'add postgresql ppa',
      :command => 'add-apt-repository ppa:pitti/postgresql',
      :unless  => 'apt-key list | grep 1024R/8683D8A2',
      :require => package('python-software-properties'),
      :before => package('postgresql')

    #ensure the postgresql key is present on the configuration hash
    default_config = HashWithIndifferentAccess.new
    default_config[:version] = postgresql_version

    configure(:postgresql => HashWithIndifferentAccess.new)

    package "postgresql-#{configuration[:postgresql][:version]}", :ensure => :installed
    package "postgresql-client-#{configuration[:postgresql][:version]}", :ensure => :installed
    package "postgresql-contrib-#{configuration[:postgresql][:version]}", :ensure => :installed
    package "postgresql-client-common", :ensure => :installed
    package "postgresql-common", :ensure => :installed
    package 'libpq-dev', :ensure => :installed

    service "postgresql-#{configuration[:postgresql][:version]}",
      :alias      => 'postgresql',
      :ensure     => :running,
      :hasstatus  => true,
      :require    => [
        package('postgresql')
      ]

    file "/etc/postgresql/#{configuration[:postgresql][:version]}/main/pg_hba.conf",
      :ensure  => :present,
      :content => template(File.join(File.dirname(__FILE__), 'templates', 'pg_hba.conf.erb')),
      :require => package('postgresql'),
      :mode    => '600',
      :owner   => 'postgres',
      :group   => 'postgres',
      :notify  => service("postgresql")

    file "/etc/postgresql/#{configuration[:postgresql][:version]}/main/postgresql.conf",
      :ensure  => :present,
      :content => template(File.join(File.dirname(__FILE__), 'templates', 'postgresql.conf.erb')),
      :require => package('postgresql'),
      :mode    => '600',
      :owner   => 'postgres',
      :group   => 'postgres',
      :notify  => service("postgresql")
  end

  # Install the <tt>pg</tt> rubygem and dependencies
  def postgresql_gem
    gem 'pg', :require => service("postgresql")
    gem 'postgres', :require => service("postgresql")
  end

  # Grant the database user specified in the current <tt>database_environment</tt>
  # permisson to access the database with the supplied password
  def postgresql_user
    psql "CREATE USER #{database_environment[:username]} WITH PASSWORD '#{database_environment[:password]}'",
      :alias    => "postgresql_user",
      :unless   => psql_query('\\\\du') + "| grep #{database_environment[:username]}",
      :require  => service("postgresql")
  end

  # Create the database from the current <tt>database_environment</tt>
  def postgresql_database
    exec "postgresql_database",
      :command  => "/usr/bin/createdb -O #{database_environment[:username]} #{database_environment[:database]}",
      :unless   => "/usr/bin/psql -l | grep #{database_environment[:database]}",
      :user     => 'postgres',
      :require  => exec('postgresql_user'),
      :before   => exec('rake tasks'),
      :notify   => exec('rails_bootstrap')
  end

private

  def psql(query, options = {})
    name = options.delete(:alias) || "psql #{query}"
    hash = {
      :command => psql_query(query),
      :user => 'postgres'
    }.merge(options)
    exec(name,hash)
  end

  def psql_query(sql)
    "/usr/bin/psql -c \"#{sql}\""
  end

end