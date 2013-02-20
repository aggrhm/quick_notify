require "quick_notify/version"
require "quick_notify/notification"
require "quick_notify/device"
require "quick_notify/apns"
require "quick_notify/sender"

module QuickNotify
  # Your code goes here...

  if defined?(Rails)
    # load configuration
    class Railtie < Rails::Railtie
      initializer "quick_notify.configure" do
        config_file = Rails.root.join("config", "quick_notify.yml")
        QuickNotify.configure(YAML.load_file(config_file)[Rails.env]) unless config_file.nil?
      end
    end
  end

  class << self

    def configure(opts)
      @options = opts.with_indifferent_access
      # set any default opts here
    end

    def options
      @options ||= {}
    end

  end
end
