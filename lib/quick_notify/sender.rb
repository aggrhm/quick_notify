module QuickNotify

  class Sender

    def self.send_ios_notification(device, notif)
      @apns ||= APNS.new(QuickNotify.options[:apns])
      an = APNS::Notification.new(device.token, notif.message)
      status = @apns.write(an.package)
      return status
    end

  end

end
