module QuickNotify
  module Event

    def self.included(base)
      base.send :include, QuickNotify::EventListener
      base.send :extend, ClassMethods
    end

    STATES = {:new => 1, :processed => 2}

    module ClassMethods

      def register(action, opts)
        e = self.new
        e.action = action
        e.actor = opts[:actor]
        e.model = opts[:model]
        e.publisher = opts[:publisher]
        e.meta = opts[:meta] || opts[:metadata] || {}

        e.state! :new
        e.save
        # run job to process
        Job.run_later :event, e, :process
        Job.run_later :event, self, :cleanup
        return e
      end

      def publish(action, model, actor=nil, publisher=nil, opts={})
        if model.is_a?(Hash)
          self.register(action, model)
        else
          self.register(action, {model: model, actor: actor, publisher: publisher, meta: opts})
        end
      end

      ##
      # NOTE: deprecated
      def add(action, model, user, opts={})
        self.publish(action, model, user, opts.delete(:publisher), opts)
      end

      def cleanup
        age_days = QuickNotify.options[:max_event_age] || 365
        oldest_t = age_days.days.ago
        self.processed.before(oldest_t).destroy_all
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

          field :cpid, as: :cluster_parent_id
          field :cids, as: :cluster_children_ids, type: Array, default: []

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
        scope :with_action, lambda {|acs|
          acs = [acs] unless acs.is_a?(Array)
          where('at' => {'$in' => acs})
        }
        scope :before, lambda {|time|
          where('c_at' => {'$lt' => time})
        }
        scope :is_cluster_parent, lambda {
          where('cpid' => nil)
        }
        scope :with_model, lambda {|cls, id|
          where(mc: cls.to_s, mi: id)
        }
        scope :with_actor, lambda {|cls, id|
          where(ac: cls.to_s, ai: id)
        }
        scope :with_publisher, lambda {|cls, id|
          where(pc: cls.to_s, pi: id)
        }
      end

      def on_all(&block)
        QuickNotify.event_handlers << {
          model: nil,
          action: nil,
          callback: block
        }
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
      if m.nil?
        self.model_class = nil
        self.model_id = nil
      else
        self.model_class = m.class.to_s
        self.model_id = m.id
      end
    end

    def model
      return nil if self.model_class.nil?
      cls = self.model_class.constantize
      cls.find(self.model_id)
    end

    def publisher=(m)
      if m.nil?
        self.publisher_class = nil
        self.publisher_id = nil
      else
        self.publisher_class = m.class.to_s
        self.publisher_id = m.id
      end
    end

    def publisher
      return nil if self.publisher_class.nil?
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
      # detect cluster
      cl_evs = self.find_clustered_events
      self.cluster_children_ids = cl_evs.collect(&:id)
      # call handlers
      hs = QuickNotify.event_handlers.select {|handler|
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
        rescue => e
          Rails.logger.info "------- APPEVENT EVENT HANDLER ERROR -------"
          Rails.logger.info e
          Rails.logger.info e.backtrace.join("\n\t")
        end
      end

      #self.build_body
      self.state! :processed
      self.save
      cl_evs.each {|ev|
        ev.cluster_parent_id = self.id
        ev.save
      }

      # call after handlers

      ahs = QuickNotify.event_after_handlers.select {|handler|
        handler[:action] == self.action || handler[:action_model] == self.action_model
      }
      ahs = ahs + (@process_handlers || [])
      ahs.each {|handler|
        begin
          handler[:callback].call(self)
        rescue => e
          Rails.logger.info "------- APPEVENT RUN HANDLER ERROR -------"
          Rails.logger.info e
          Rails.logger.info e.backtrace.join("\n\t")
        end
      }
    end

    def run(blk)
      @process_handlers ||= []
      @process_handlers << {callback: blk}
    end

    def find_clustered_events
      evs = AppEvent.where(ac: self.actor_class, ai: self.actor_id, mc: self.model_class, mi: self.model_id, pc: self.publisher_class, pi: self.publisher_id, at: self.action, c_at: {'$gte' => (self.created_at - 3.minutes)}).all
      return evs.select{|ev| ev.id.to_s != self.id.to_s}
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
      ret[:actor_id] = self.actor_id.to_s
      ret[:actor_class] = self.actor_class
      ret[:model_id] = self.model_id.to_s
      ret[:model_class] = self.model_class
      ret[:publisher_class] = self.publisher_class
      ret[:meta] = self.meta
      ret[:body] = self.body
      ret[:created_at] = self.created_at.utc.to_i unless self.created_at.nil?
      ret[:cluster_parent_id] = self.cluster_parent_id ? self.cluster_parent_id.to_s : nil
      ret[:cluster_children_ids] = self.cluster_children_ids.collect(&:to_s)
      return ret
    end

  end
end
