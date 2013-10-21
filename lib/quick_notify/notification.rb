module QuickNotify
  module Notification

    PLATFORMS = {:email => 1, :ios => 2, :android => 3}
    STATUS_CODES = {:sending => 1, :sent => 2, :error => 3}

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def add(user, action, opts)
        n = self.new
        n.action = self.actions[action.to_sym]
        n.user = user
        n.opts = opts[:opts]
        n.delivery_vars = opts[:delivery_vars]
        saved = n.save
        if saved
          self.release_old_for(user.id)
        end
        return n
      end

      def quick_notify_notification_keys_for(db)
        if db == :mongomapper
          key :ac,  Integer
          key :uid, ObjectId
          key :oph, Hash
          key :sls, Array
          key :dvs, Array

          attr_alias :action, :ac
          attr_alias :user_id, :uid
          attr_alias :opts, :oph
          attr_alias :status_log, :sls
          attr_alias :delivery_vars, :dvs

          timestamps!

        elsif db == :mongoid
          field :ac, as: :action, type: Integer
          field :uid, as: :user_id, type: Moped::BSON::ObjectId
          field :oph, as: :opts, type: Hash
          field :sls, as: :status_log, type: Array, default: []
          field :dvs, as: :delivery_vars, type: Array

          mongoid_timestamps!

        end
        belongs_to :user, :foreign_key => :uid
      end

      def actions
        @actions ||= {}
      end

      def device_class_is(cls)
        @device_class = cls
      end

      def device_class
        @device_class || ::Device
      end

      def add_action(act, val)
        self.actions[act] = val
      end

      def release_old_for(user_id)
        self.delete_all(:uid => user_id, :created_at => {'$lte' => 30.days.ago})
      end

    end

    ## DELIVERY

    def deliver
      self.platforms_for_delivery.each do |plat|
        case plat
        when :ios
          self.deliver_ios
        end
      end
    end

    def deliver_email

    end

    def deliver_ios
      self.class.device_class.registered_to(self.user.id).running_ios.each do |device|
        if device.is_dormant?
          device.unregister
        else
          self.log_status(:ios, :sending, device.id)
          ret = QuickNotify::Sender.send_ios_notification(device, self)
          self.log_status(:ios, (ret == true ? :sent : :error), device.id)
        end
      end
    end

    def deliver_android

    end

    def log_status(plat, code, note=nil)
      self.status_log << {plat: plat, code: STATUS_CODES[code], note: note.to_s}
      self.save
    end

    ## OVERRIDES

    def platforms_for_delivery
      return []
    end

    def message

    end

    def subject

    end

    ## HELPERS

    def action_sym
      self.class.actions.rassoc(self.action).first
    end

    def delivery_opts
      ret = {}
      ret['act'] = self.action
      self.delivery_vars.each do |var|
        ret[var] = self.opts[var]
      end unless self.delivery_vars.nil?
      return ret
    end

  end
end
