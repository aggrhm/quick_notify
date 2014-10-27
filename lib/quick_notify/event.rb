module QuickNotify
  module Event
    def self.included(base)
      base.extend ClassMethods
    end

    STATES = {:new => 1, :processed => 2}

    module ClassMethods
      def publish(action, model, user, publisher, opts={})
        e = self.new
        e.actor=user
        e.action=action.to_s
        e.model=model
        e.publisher = publisher

        e.meta.merge!(opts)
        e.state! :new
        e.save
        # run job to process
        Job.run_later :event, e, :process
        Job.run_later :event, self, :cleanup
      end

      def add(action, model, user, opts={})
        self.publish(action, model, user, opts.delete(:publisher), opts)
      end

      def cleanup
        limit = QuickNotify.options[:event_limit] || 5000
        while self.processed.count > limit
          self.processed.asc(:created_at).first.destroy
        end
      end

      def quick_notify_event_keys_for!(db)
        case db
        when :mongoid
          include MongoHelper::Model

          field :ac, as: :actor_class, type: String
          field :ai, as: :actor_id
          field :mc, as: :model_class, type: String
          field :mi, as: :model_id
          field :pc, as: :publisher_class, type: String
          field :pi, as: :publisher_id
          field :at, as: :action, type: String
          field :st, as: :state, type: Integer
          #field :bd, as: :body, type: String
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
          processed.desc(:created_at)
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

      def on_all(&block)
        handlers << {
          model: nil,
          action: nil,
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
        cls = self.actor_class.constantize
        return cls.find(self.actor_id)
      end
    end

    def model=(m)
      self.model_class = m.class.to_s
      self.model_id = m.id
    end

    def model
      return nil if self.model_class.nil?
      cls = self.model_class.constantize
      cls.find(self.model_id)
    end

    def publisher=(m)
      self.publisher_class = m.class.to_s
      self.publisher_id = m.id
    end

    def publisher
      cls = self.publisher_class.constantize
      cls.find(self.publisher_id)
    end

    def action_model
      return nil if self.action.nil?
      return nil if !self.action.include?('.')
      self.action[0, self.action.rindex('.')]
    end

    def action_verb
      return nil if self.action.nil?
      return self.action if !self.action.include?('.')
      self.action[self.action.rindex('.')+1..-1]
    end

    def actor_name
      actor_s = self.actor ? self.actor.name : "Someone"
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
        elsif handler[:model] == nil
          true
        else
          false
        end
      }
      hs.each do |handler|
        begin
          handler[:callback].call(self)
        rescue Exception => e
          Rails.logger.info "------- APPEVENT EVENT HANDLER ERROR -------"
          Rails.logger.info e
          Rails.logger.info e.backtrace.join("\n\t")
        end
      end

      #self.build_body
      self.state! :processed
      self.save

      @process_handlers.each {|h|
        begin
          h.call(self)
        rescue Exception => e
          Rails.logger.info "------- APPEVENT RUN HANDLER ERROR -------"
          Rails.logger.info e
          Rails.logger.info e.backtrace.join("\n\t")
        end
      } unless @process_handlers.nil?
    end

    def run(blk)
      @process_handlers ||= []
      @process_handlers << blk
    end

    def body
      model_s = self.meta["model_class"] || self.action_model
      str = "#{model_s} #{self.action_verb}"
      return str
    end

    def to_api(opt=:default)
      ret = {}
      ret[:id] = self.id.to_s
      ret[:action] = self.action
      ret[:action_model] = self.action_model
      ret[:action_verb] = self.action_verb
      ret[:actor_id] = self.actor_id
      ret[:actor_class] = self.actor_class
      ret[:model_class] = self.model_class
      ret[:publisher_class] = self.publisher_class
      ret[:meta] = self.meta
      ret[:body] = self.body
      ret[:created_at] = self.created_at.utc.to_i unless self.created_at.nil?
      return ret
    end

  end
end
