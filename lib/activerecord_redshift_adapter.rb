require 'activerecord_redshift_adapter/version'
require 'activerecord_redshift/table_manager'
require 'monkeypatch_activerecord'
require 'monkeypatch_arel'
Dir[File.join(File.expand_path(File.dirname(__FILE__)), 'tasks', '*.rake')].each { |rake_task| load rake_task } if defined?(Rake)

module ActiveRecord
  module ConnectionAdapters
    module ActiverecordRedshift
      module CoreExt
        module ActiveRecord
          extend ActiveSupport::Concern
          module ClassMethods
            def vacuum_redshift_table
              if connection.respond_to?(:vacuum_table) && table_name.present?
                connection.vacuum_table(table_name)
              else
                method_missing(:vacuum_redshift_table)
              end
            end
            def analyse_redshift_table
              if connection.respond_to?(:vacuum_table) && table_name.present?
                connection.vacuum_table(table_name)
              else
                method_missing(:analyse_redshift_table)
              end
            end
          end
        end
      end
    end
  end
end

ActiveRecord::Base.send :include, ActiveRecord::ConnectionAdapters::ActiverecordRedshift::CoreExt::ActiveRecord