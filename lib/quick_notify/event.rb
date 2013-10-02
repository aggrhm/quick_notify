module QuickNotify
  module Event
    def self.included(base)
      base.extend ClassMethods
    end

    STATES = {:new => 1, :processed => 2}

    module ClassMethods
      def add(action, model, user, opts={})
        e = self.new
        e.actor=user
        e.action=action.to_s
        e.model=model

        opts['user'] ||= user.to_api(:min)
        opts['model'] ||= model.to_api(:min)
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
          field :mc, as: :model_class, type: String
          field :mi, as: :model_id, type: Moped::BSON::ObjectId
          field :at, as: :action, type: String
          field :st, as: :state, type: Integer
          field :bd, as: :body, type: String
          field :mth, as: :meta, type: Hash, default: {}

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

      def on_model(model, &block)
        handlers << {
          model: model,
          action: nil,
          callback: block
        }
      end

      def on_action(action, &block)
        handlers << {
          model: action[0, action.rindex('.')],
          action: action,
          callback: block
        }
      end

      def handlers
        @handlers ||= []
      end

    end

    ## INSTANCE METHODS

    def actor=(m)
      if m.nil?
        self.actor_class = nil
        self.actor_id = nil
      else
        self.actor_class = m.class.to_s
        self.actor_id = m.id
      end
    end

    def actor
      if self.actor_class.nil?
        return nil
      else
        cls = Object.const_get(self.actor_class)
        return cls.find(self.actor_id)
      end
    end

    def model=(m)
      self.model_class = m.class.to_s
      self.model_id = m.id
    end

    def model
      cls = Object.const_get(self.model_class)
      cls.find(self.model_id)
    end

    def action_model
      self.action[0, self.action.rindex('.')]
    end

    def action_str
      self.action[self.action.rindex('.')+1..-1]
    end


    def process
      # call handlers
      hs = self.class.handlers.select {|handler|
        if handler[:model] == self.action_model
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

      @process_handlers.each {|h| h.call(self)} unless @process_handlers.nil?
    end

    def run(blk)
      @process_handlers ||= []
      @process_handlers << blk
    end

    def set_body!(body)
      self.body = body
      self.save
    end

    def build_body
      return unless self.body.nil?
      actor_s = self.actor ? self.actor.name : "Someone"
      model_s = self.meta["model_class"] || self.action_model

      body = "#{actor_s} #{self.action_str} #{model_s}"

      body << " '#{self.meta["model_title"]}'" if self.meta["model_title"]

      body << " #{self.meta["fields"].join(', ')}" if self.meta["fields"]

      body << "."

      self.body = body
    end

    def to_api(opt=:default)
      ret = {}
      ret[:id] = self.id.to_s
      ret[:action] = self.action
      ret[:actor_class] = self.actor_class
      ret[:model_class] = self.model_class
      ret[:meta] = self.meta
      ret[:body] = self.body
      ret[:created_at] = self.created_at.utc.to_i
      return ret
    end

  end
end
