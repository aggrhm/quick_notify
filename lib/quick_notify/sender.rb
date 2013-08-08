module QuickNotify

  class Sender

    def self.send_ios_notification(device, notif)
      @apns ||= APNS.new(QuickNotify.options[:apns])
      # build data
      data = {:alert => notif.message, :other => notif.delivery_opts}
      QuickNotify.log("QuickNotify::Sender:: Sending iOS notifcation to #{device.token}.")
      an = APNS::Notification.new(device.token, data)
      status = @apns.write(an.package)
      return status
    end

  end

end
