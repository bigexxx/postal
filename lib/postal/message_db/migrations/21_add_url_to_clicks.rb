# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddUrlToClicks < Postal::MessageDB::Migration

        def up
          @database.query("ALTER TABLE `#{@database.database_name}`.`clicks` ADD COLUMN `url` TEXT DEFAULT NULL AFTER `link_id`")
        end

      end
    end
  end
end
