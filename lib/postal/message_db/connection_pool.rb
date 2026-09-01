# frozen_string_literal: true

module Postal
  module MessageDB
    class ConnectionPool

      attr_reader :connections

      def initialize
        @connections = []
        @lock = Mutex.new
      end

      def use
        retried = false
        connection = nil
        begin
          connection = retried ? establish_connection : checkout

          yield connection
        rescue Mysql2::Error => e
          if e.message =~ /(lost connection|gone away|not connected)/i
            connection.close if connection && !connection.closed?
            connection = nil

            unless retried
              retried = true
              retry
            end
          end

          raise
        ensure
          checkin(connection) if connection
        end
      end

      private

      def checkout
        @lock.synchronize do
          return @connections.pop unless @connections.empty?
        end

        add_new_connection
        checkout
      end

      def checkin(connection)
        @lock.synchronize do
          @connections << connection
        end
      end

      def add_new_connection
        @lock.synchronize do
          @connections << establish_connection
        end
      end

      def establish_connection
        Mysql2::Client.new(
          host: Postal::Config.message_db.host,
          username: Postal::Config.message_db.username,
          password: Postal::Config.message_db.password,
          port: Postal::Config.message_db.port,
          encoding: Postal::Config.message_db.encoding
        )
      end

    end
  end
end
