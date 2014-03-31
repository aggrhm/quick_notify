module QuickNotify
  module Device

    OS_TYPES = {:ios => 1, :android => 2}

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def quick_notify_device_keys_for(db)
        if db == :mongomapper
          key :os,  Integer
          key :tk,  String
          key :pn,  String
          key :did,  String
          key :uid, ObjectId
          key :a_at, Time

          attr_alias :token, :tk
          attr_alias :platform_notes, :pn
          attr_alias :udid, :did
          attr_alias :user_id, :uid
          attr_alias :accessed_at, :a_at

          timestamps!

        elsif db == :mongoid
          field :os, type: Integer
          field :tk, as: :token, type: String
          field :pn, as: :platform_notes, type: String
          field :did, as: :udid, type: String
          field :uid, as: :user_id
          field :a_at, as: :accessed_at, type: Time

          mongoid_timestamps!

        end

        enum_methods! :os, OS_TYPES

        scope :registered_to, lambda{|uid|
          where(:uid => uid).desc(:a_at)
        }
        scope :with_os, lambda{|os|
          os = OS_TYPES[os] if os.is_a? Symbol
          where(:os => os)
        }
        scope :running_ios, lambda{
          where(:os => 1)
        }

      end

      def register(udid, os, token, user, opts={})
        return nil if os.blank? || udid.blank? || token.blank?
        d = self.where(did: udid).first || self.new
        d.os = os.to_i
        d.udid = udid
        d.user_id = user.id
        d.token = token
        d.accessed_at = Time.now
        d.save
        return d
      end

      def unregister(udid)
        self.where(did: udid).destroy_all
      end

    end

    ## INSTANCE METHODS

    def is_dormant?
      return false if self.accessed_at.nil?

      self.accessed_at < 1.month.ago
    end

    def unregister
      self.destroy
    end

  end
end
