# lib/tasks/databases.rake

# Public: This Rake file tries to add what rails provides on the
# databases.rake but for building on top of custom databases.
# Basically we get the nice db:migrate but for using it on a different DB than
# the default, by calling it with the namespace defined here.
#
# In order to be able to use the default rails rake commands but on a different
# DB, we are first updating the Rails.application.config.paths and then
# calling the original rake task. Rails.application.config.paths is getting
# loaded and available as soon as we call rake since the rakefile in a rails
# project declares that. Look at Rakefile in the project root for more details.

# Rails tasks only manage mysql, sqlite and postgresql by default. We need to hack rake task.
# Let's hack this.
# Origin method : rails/activerecord/lib/active_record/railties/databases.rake

# Let's the possibiliby to replace some rails task that does not support redshift to rewrite them with redshift.
Rake::TaskManager.class_eval do
  def replace_task(task_name, task_scope)
    scope_backup = @scope
    @scope = Rake::Scope.new(task_scope)
    task_name_full = @scope.path_with_task_name(task_name)
    @tasks[task_name_full].clear
    @tasks[task_name_full] = yield
    @scope = scope_backup
  end
end

Rake.application.replace_task('purge', 'db:test') do
  task :purge => [:environment, :load_config] do
    abcs = ActiveRecord::Base.configurations
    case abcs['test']['adapter']
    when /mysql/
      ActiveRecord::Base.establish_connection(:test)
      ActiveRecord::Base.connection.recreate_database(abcs['test']['database'], mysql_creation_options(abcs['test']))
    when /postgresql/
      ActiveRecord::Base.clear_active_connections!
      drop_database(abcs['test'])
      create_database(abcs['test'])
    when /redshift/
      ActiveRecord::Base.clear_active_connections!
      drop_database(abcs['test'])
      create_database(abcs['test'])
    when /sqlite/
      dbfile = abcs['test']['database']
      File.delete(dbfile) if File.exist?(dbfile)
    when 'sqlserver'
      test = abcs.deep_dup['test']
      test_database = test['database']
      test['database'] = 'master'
      ActiveRecord::Base.establish_connection(test)
      ActiveRecord::Base.connection.recreate_database!(test_database)
    when "oci", "oracle"
      ActiveRecord::Base.establish_connection(:test)
      ActiveRecord::Base.connection.structure_drop.split(";\n\n").each do |ddl|
        ActiveRecord::Base.connection.execute(ddl)
      end
    when 'firebird'
      ActiveRecord::Base.establish_connection(:test)
      ActiveRecord::Base.connection.recreate_database!
    else
      raise "Task not supported by '#{abcs['test']['adapter']}'"
    end
  end
end

Rake.application.replace_task('charset', 'db') do
  task :charset => [:environment, :load_config] do
    config = ActiveRecord::Base.configurations[Rails.env]
    case config['adapter']
    when /mysql/
      ActiveRecord::Base.establish_connection(config)
      puts ActiveRecord::Base.connection.charset
    when /postgresql/
      ActiveRecord::Base.establish_connection(config)
      puts ActiveRecord::Base.connection.encoding
    when /redshift/
      ActiveRecord::Base.establish_connection(config)
      puts ActiveRecord::Base.connection.encoding
    when /sqlite/
      ActiveRecord::Base.establish_connection(config)
      puts ActiveRecord::Base.connection.encoding
    else
      $stderr.puts 'sorry, your database adapter is not supported yet, feel free to submit a patch'
    end
  end
end

Rake.application.replace_task('load', 'db:structure') do
  task :load => [:environment, :load_config] do
    config = current_config
    filename = ENV['DB_STRUCTURE'] || File.join(Rails.application.config.paths['db'].first, "structure.sql")
    case config['adapter']
    when /mysql/
      ActiveRecord::Base.establish_connection(config)
      ActiveRecord::Base.connection.execute('SET foreign_key_checks = 0')
      IO.read(filename).split("\n\n").each do |table|
        ActiveRecord::Base.connection.execute(table)
      end
    when /postgresql/
      set_psql_env(config)
      `psql -f "#{filename}" #{config['database']}`
    when /redshift/
      set_psql_env(config)
      `psql -f "#{filename}" #{config['database']}`
    when /sqlite/
      dbfile = config['database']
      `sqlite3 #{dbfile} < "#{filename}"`
    when 'sqlserver'
      `sqlcmd -S #{config['host']} -d #{config['database']} -U #{config['username']} -P #{config['password']} -i #{filename}`
    when 'oci', 'oracle'
      ActiveRecord::Base.establish_connection(config)
      IO.read(filename).split(";\n\n").each do |ddl|
        ActiveRecord::Base.connection.execute(ddl)
      end
    when 'firebird'
      set_firebird_env(config)
      db_string = firebird_db_string(config)
      sh "isql -i #{filename} #{db_string}"
    else
      raise "Task not supported by '#{config['adapter']}'"
    end
  end
end

Rake.application.replace_task('dump', 'db:structure') do
  task :dump => [:environment, :load_config] do
    config = current_config
    filename = ENV['DB_STRUCTURE'] || File.join(Rails.application.config.paths['db'].first, "structure.sql")
    case config['adapter']
    when /mysql/, 'oci', 'oracle'
      ActiveRecord::Base.establish_connection(config)
      File.open(filename, "w:utf-8") { |f| f << ActiveRecord::Base.connection.structure_dump }
    when /postgresql/
      set_psql_env(config)
      search_path = config['schema_search_path']
      unless search_path.blank?
        search_path = search_path.split(",").map{|search_path_part| "--schema=#{Shellwords.escape(search_path_part.strip)}" }.join(" ")
      end
      `pg_dump -i -s -x -O -f #{Shellwords.escape(filename)} #{search_path} #{Shellwords.escape(config['database'])}`
      raise 'Error dumping database' if $?.exitstatus == 1
      File.open(filename, "a") { |f| f << "SET search_path TO #{ActiveRecord::Base.connection.schema_search_path};\n\n" }
    when /redshift/
      set_psql_env(config)
      search_path = config['schema_search_path']
      unless search_path.blank?
        search_path = search_path.split(",").map{|search_path_part| "--schema=#{Shellwords.escape(search_path_part.strip)}" }.join(" ")
      end
      `pg_dump -i -s -x -O -f #{Shellwords.escape(filename)} #{search_path} #{Shellwords.escape(config['database'])}`
      raise 'Error dumping database' if $?.exitstatus == 1
      File.open(filename, "a") { |f| f << "SET search_path TO #{ActiveRecord::Base.connection.schema_search_path};\n\n" }
    when /sqlite/
      dbfile = config['database']
      `sqlite3 #{dbfile} .schema > #{filename}`
    when 'sqlserver'
      `smoscript -s #{config['host']} -d #{config['database']} -u #{config['username']} -p #{config['password']} -f #{filename} -A -U`
    when "firebird"
      set_firebird_env(config)
      db_string = firebird_db_string(config)
      sh "isql -a #{db_string} > #{filename}"
    else
      raise "Task not supported by '#{config['adapter']}'"
    end
    if ActiveRecord::Base.connection.supports_migrations?
      File.open(filename, "a") { |f| f << ActiveRecord::Base.connection.dump_schema_information }
    end
    Rake::Task['db:structure:dump'].reenable
  end
end

# Let save the rails drop_database method
@rails_drop_database_method = method(:drop_database)

STATIC_REDSHIFT_DATABASE = ENV['STATIC_REDSHIFT_DATABASE'] || 'template1'

# Let's override the drop_database method
def drop_database(config)
  @rails_drop_database_method.call(config)

  case config['adapter']
  when /redshift/
    ActiveRecord::Base.establish_connection(config.merge('database' => STATIC_REDSHIFT_DATABASE, 'schema_search_path' => 'public'))
    ActiveRecord::Base.connection.drop_database config['database']
  end
end

# Let save the rails create_database method
@rails_create_database_method = method(:create_database)

# Let's override the create_database method
def create_database(config)
  @rails_create_database_method.call(config)

  case config['adapter']
  when /redshift/
    @encoding = config['encoding'] || ENV['CHARSET'] || 'utf8'
    begin
      ActiveRecord::Base.establish_connection(config.merge('database' => STATIC_REDSHIFT_DATABASE, 'schema_search_path' => 'public'))
      ActiveRecord::Base.connection.create_database(config['database'], config.merge('encoding' => @encoding))
      ActiveRecord::Base.establish_connection(config)
    rescue Exception => e
      $stderr.puts e, *(e.backtrace)
      $stderr.puts "Couldn't create database for #{config.inspect}"
    end
  end
end

