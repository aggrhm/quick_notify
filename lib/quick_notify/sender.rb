module QuickNotify

  class Sender

    def self.apns_instance
      @apns ||= APNS.new(QuickNotify.options[:apns])
    end

    def self.send_ios_notification(device, notif)
      # build data
      data = {:alert => notif.message, :other => notif.delivery_opts}
      QuickNotify.log("QuickNotify::Sender:: Sending iOS notifcation to #{device.token}.")
      an = APNS::Notification.new(device.token, data)
      status = self.apns_instance.write(an.package)
      return status
    end

    def self.send_test_ios_notification(device)
      data = {:alert => 'This is a test'}
      an = APNS::Notification.new(device.token, data)
      status = self.apns_instance.write(an.package)
      return status
    end

  end

end
