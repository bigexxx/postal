# frozen_string_literal: true

class TidyQueuedMessagesTask < ApplicationScheduledTask

  def call
    QueuedMessage.with_stale_lock.in_batches do |messages|
      messages.each do |message|
        logger.info "unlocking queued message #{message.id} (locked at #{message.locked_at} by #{message.locked_by})"
        message.unlock
      end
    end
  end

  def self.next_run_after
    quarter_to_each_hour
  end

end
