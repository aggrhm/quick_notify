module QuickNotify
  module Event
    def self.included(base)
      base.extend ClassMethods
    end

    STATES = {:new => 1, :processed => 2}

    module ClassMethods
      def add(actor, action, receiver, opts={})
        e = self.new
        e.actor=actor
        e.action=action.to_s
        e.receiver=receiver
        e.meta = opts
        e.state! :new
        e.save
        # run job to process
        Job.run_later :event, e, :process
      end

      def quick_notify_event_keys_for!(db)
        case db
        when :mongoid
          include MongoHelper

          field :ac, as: :actor_class, type: String
          field :ai, as: :actor_id, type: Moped::BSON::ObjectId
          field :rc, as: :receiver_class, type: String
          field :ri, as: :receiver_id, type: Moped::BSON::ObjectId
          field :at, as: :action, type: String
          field :mth, as: :meta, type: Hash, default: {}
          field :st, as: :state, type: Integer
          field :bd, as: :body, type: String

          mongoid_timestamps!

          enum_methods! :state, STATES

        end
        scope :processed, lambda {
          where(:st => STATES[:processed])
        }
        scope :with_body, lambda {
          where(:bd => {'$ne' => nil})
        }
        scope :published, lambda {
          processed.with_body.desc(:created_at)
        }
      end

      def on_receiver(receiver_class, action=nil, &block)
        handlers << {
          receiver_class: receiver_class.to_s,
          action: (action ? action.to_s : nil),
          actor_class: nil,
          callback: block
        }
      end

      def handlers
        @handlers ||= []
      end

    end

    ## INSTANCE METHODS

    def actor=(m)
      self.actor_class = m.class.to_s
      self.actor_id = m.id
    end

    def actor
      cls = Object.const_get(self.actor_class)
      cls.find(self.actor_id)
    end

    def receiver=(m)
      self.receiver_class = m.class.to_s
      self.receiver_id = m.id
    end

    def receiver
      cls = Object.const_get(self.receiver_class)
      cls.find(self.receiver_id)
    end


    def process
      # call handlers
      hs = self.class.handlers.select {|handler|
        if handler[:receiver_class] == self.receiver_class
          if handler[:action] == nil
            true
          elsif handler[:action] == self.action
            true
          else
            false
          end
        else
          false
        end
      }
      hs.each do |handler|
        handler[:callback].call(self)
      end

      self.build_body
      self.state! :processed
      self.save
    end

    def build_body
      return unless self.body.nil?
      actor_s = self.meta["actor_name"] || self.actor_class
      receiver_s = self.meta["receiver_class"] || self.receiver_class
      body = "#{actor_s} #{self.action} #{receiver_s.downcase}"
      body << " '#{self.meta["receiver_name"]}'" if self.meta["receiver_name"]
      body << " #{self.meta["fields"].join(', ')}" if self.meta["fields"]
      body << "."
      self.body = body
    end

    def to_api(opt=:default)
      ret = {}
      ret[:id] = self.id.to_s
      ret[:action] = self.action
      ret[:actor_class] = self.actor_class
      ret[:receiver_class] = self.receiver_class
      ret[:meta] = self.meta
      ret[:body] = self.body
      ret[:created_at] = self.created_at.utc.to_i
      return ret
    end

  end
end
