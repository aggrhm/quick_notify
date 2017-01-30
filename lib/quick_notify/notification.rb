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
        n.event = opts[:event] if opts[:event]
        n.user = user
        n.message = opts[:message]
        n.short_message = opts[:short_message]
        n.full_message = opts[:full_message]
        n.html_message = opts[:html_message]
        n.subject = opts[:subject]
        n.delivery_platforms = opts[:delivery_platforms]
        n.meta = opts[:metadata] || {}
        n.delivery_settings = opts[:delivery_settings] || {}
        saved = n.save
        if saved
          self.release_old_for(user.id)
        end
        return n
      end

      def quick_notify_notification_keys_for!(db)
        if db == :mongomapper
          key :ac,  Integer
          key :uid, ObjectId
          key :oph, Hash
          key :sls, Array
          key :dvs, Array

          attr_alias :action, :ac
          attr_alias :user_id, :uid
          attr_alias :meta, :oph
          attr_alias :status_log, :sls

          timestamps!

        elsif db == :mongoid
          include MongoHelper::Model
          field :ac, as: :action, type: Integer
          field :uid, as: :user_id
          field :rm, as: :message, type: String
          field :sm, as: :short_message, type: String
          field :fm, as: :full_message, type: String
          field :hm, as: :html_message, type: String
          field :sb, as: :subject, type: String
          field :pfs, as: :delivery_platforms, type: Array, default: []
          field :oph, as: :meta, type: Hash
          field :sls, as: :status_log, type: Array, default: []
          field :dsh, as: :delivery_settings, type: Hash, default: {}
          field :eid, as: :event_id
          field :ea, as: :event_action, type: String

          mongoid_timestamps!

        end
      end

      def actions
        @actions ||= {event: 1}
      end

      def device_class
        QuickNotify.Device
      end

      def event_class
        QuickNotify.Event
      end

      def add_action(act, val)
        self.actions[act] = val
      end

      def release_old_for(user_id)
        self.delete_all(:uid => user_id, :created_at => {'$lte' => 30.days.ago})
      end

    end

    def event
      return nil if self.event_id.blank?
      @event ||= QuickNotify.Event.find(self.event_id)
    end

    def event=(ev)
      if ev.nil?
        self.event_id = nil
        self.event_action = nil
        @event = nil
      else
        self.event_id = ev.id
        self.event_action = ev.action
        @event = ev
      end
      @event
    end

    def user
      return nil if self.user_id.blank?
      @user ||= QuickNotify.User.find(self.user_id)
    end

    def user=(u)
      if u.nil?
        self.user_id = nil
        @user = nil
      else
        self.user_id = u.id
        @user = u
      end
      @user
    end

    ## DELIVERY

    def deliver
      self.delivery_platforms.each do |plat|
        case plat.to_sym
        when :ios
          self.deliver_ios
        when :email
          self.deliver_email
        end
      end
    end

    def deliver_email
      begin
        ml = QuickNotify::Mailer.notification_email(self)
        ml.respond_to?(:deliver_now) ? ml.deliver_now : ml.deliver
        self.log_status(:email, :sent, self.user.email)
      rescue => e
        self.log_status(:email, :error, self.user.email)
        puts e
        puts e.backtrace.join("\n\t")
      end
    end

    def deliver_ios
      QuickNotify.Device.registered_to(self.user.id).running_ios.each do |device|
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

    def metadata
      return self.meta
    end

    def log_status(plat, code, note=nil)
      self.status_log << {plat: plat, code: STATUS_CODES[code], note: note.to_s}
      self.save
    end

    ## HELPERS

    def action_sym
      self.class.actions.rassoc(self.action).first
    end

    def delivery_settings_for(type)
      return (self.delivery_settings[type.to_s] || self.delivery_settings[type.to_sym] || {}).with_indifferent_access
    end

  end
end
